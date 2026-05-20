//
//  RunSummaryTests.swift
//  Agenic Load-BalancerTests
//
//  Created by Claude on 5/6/26.
//
//  Phase 7.2: tests for structured outcome classification. Exercises the
//  Sendable RunSummary value type, the RunSummarizing protocol, the
//  default factory, RunOutcomeRecord stamping, SnapshotArchive round-trip
//  of the new fields, and the RunDispatcher's post-success summarization
//  hook (success path + error path + unavailable path).
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@MainActor
@Suite("Phase 7.2 run summary")
struct RunSummaryTests {
    // MARK: Helpers

    private struct StubExecutableResolver: CLIExecutableResolving {
        let resolvedPath: String?
        let version: String?

        func resolveExecutable(named binaryName: String) -> String? { resolvedPath }
        func versionString(executablePath: String) async -> String? { version }
    }

    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "RunSummaryTests-\(UUID().uuidString)",
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    private static func makePlan(prompt: String = "Implement the run summary panel.") -> RunPlan {
        let draft = ProviderCatalog.defaultProfiles[0]
        let snapshot = AgentProviderSnapshot(
            identifier: draft.identifier,
            displayName: draft.displayName,
            binaryName: draft.binaryName,
            installCommand: draft.installCommand,
            verificationCommand: draft.verificationCommand,
            supportedExecutionModes: draft.supportedExecutionModes,
            capabilities: draft.capabilities,
            installedState: .available,
            authState: .authenticated,
            isEnabled: true
        )
        let score = RoutingScoreBreakdown(
            providerID: draft.identifier,
            providerName: draft.displayName,
            mode: .implementation,
            totalScore: 0.9,
            availabilityScore: 1,
            capabilityScore: 0.9,
            limitScore: 0.85,
            accuracyScore: 0.92,
            speedScore: 0.7,
            costScore: 0.95,
            rationale: "Phase 7.2 test plan",
            estimatedCostUSD: 0.01,
            limitImpact: "Low pressure",
            coordinationWarning: ""
        )
        return RunPlan(
            providerSnapshot: snapshot,
            providerID: draft.identifier,
            providerName: draft.displayName,
            prompt: prompt,
            projectID: nil,
            projectName: nil,
            projectRootPath: nil,
            mode: .implementation,
            score: score,
            promptExcerptSyncEnabled: false
        )
    }

    private static func makeDispatcher(
        runner: AgentRunning,
        summarizer: any RunSummarizing,
        resolverPath: String? = "/usr/local/bin/codex"
    ) -> RunDispatcher {
        let factory: @Sendable (String, ProviderCommandProfileSnapshot?) -> AgentCLIAdapter = { id, profile in
            GenericCLIAdapter(
                providerID: id,
                commandProfile: profile,
                executableResolver: StubExecutableResolver(resolvedPath: resolverPath, version: "0.0.0")
            )
        }
        return RunDispatcher(
            runner: runner,
            adapterFactory: factory,
            summarizer: summarizer
        )
    }

    private static func awaitSummary(
        _ dispatcher: RunDispatcher,
        timeout: TimeInterval = 3.0
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch dispatcher.aiSummaryStatus {
            case .succeeded, .failed, .unavailable:
                return
            default:
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

    // MARK: Value-type round-trip

    @Test func runSummaryFilesChangedJSONRoundTripsThroughDecode() {
        let summary = RunSummary(
            filesChanged: ["Sources/A.swift", "Sources/B.swift"],
            testsPassed: 12,
            testsFailed: 0,
            oneLineDescription: "Refactored A and B.",
            suggestedAccuracyRating: .correct
        )
        let json = summary.filesChangedJSON
        #expect(json.contains("Sources/A.swift"))
        let roundTripped = RunSummary.decodeFilesChanged(json)
        #expect(roundTripped == summary.filesChanged)
        // Empty / malformed inputs decode to an empty array.
        #expect(RunSummary.decodeFilesChanged(nil) == [])
        #expect(RunSummary.decodeFilesChanged("nope") == [])
    }

    @Test func applyRunSummaryStampsOptionalFieldsAndPreservesManualRating() {
        let outcome = RunOutcomeRecord(providerID: "openai.codex")
        // Pre-existing manual rating must NOT be clobbered by the AI suggestion.
        outcome.accuracyRating = AccuracyRating.minorFixNeeded.rawValue

        let summary = RunSummary(
            filesChanged: ["dashboard.swift"],
            testsPassed: nil,
            testsFailed: nil,
            oneLineDescription: "Wired the heatmap.",
            suggestedAccuracyRating: .correct
        )
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        outcome.applyRunSummary(summary, generatedAt: timestamp)

        #expect(outcome.aiOneLineDescription == "Wired the heatmap.")
        #expect(outcome.aiTestsPassed == nil)
        #expect(outcome.aiTestsFailed == nil)
        #expect(outcome.aiSuggestedAccuracyRating == AccuracyRating.correct.rawValue)
        #expect(outcome.aiSummaryGeneratedAt == timestamp)
        #expect(outcome.aiFilesChanged == ["dashboard.swift"])
        #expect(outcome.aiRunSummary?.oneLineDescription == "Wired the heatmap.")
        // Manual accuracy rating is preserved.
        #expect(outcome.accuracyRating == AccuracyRating.minorFixNeeded.rawValue)
    }

    // MARK: NoopRunSummarizer + factory

    @Test func noopRunSummarizerThrowsUnavailable() async {
        let summarizer = NoopRunSummarizer(reason: "Stubbed-off for tests.")
        let input = RunSummaryInput(
            prompt: "x",
            providerID: "test",
            providerName: "Test",
            mode: .implementation,
            exitCode: 0,
            durationSeconds: 0,
            standardOutput: "",
            standardError: ""
        )
        do {
            _ = try await summarizer.summarize(input: input)
            Issue.record("Expected unavailable error.")
        } catch let error as RunSummaryError {
            switch error {
            case .unavailable(let reason): #expect(reason == "Stubbed-off for tests.")
            default: Issue.record("Expected .unavailable, got \(error)")
            }
        } catch {
            Issue.record("Expected RunSummaryError, got \(error)")
        }
    }

    @Test func factoryReturnsNoopWhenAvailabilityIsUnavailable() async {
        let summarizer = RunSummarizerFactory.makeDefault(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.appleIntelligenceNotEnabled)
        )
        #expect(summarizer is NoopRunSummarizer)
    }

    // MARK: Truncation

    @Test func runSummaryInputTruncatesLargeBuffersFromTail() {
        // Build a 20 000-char buffer of repeating digits and verify only
        // the last `maxBufferBytes` characters survive, with a "[truncated]"
        // marker prepended so the model knows content was dropped.
        let large = String(repeating: "0123456789", count: 2_000)
        let input = RunSummaryInput(
            prompt: "x",
            providerID: "test",
            providerName: "Test",
            mode: .testBuild,
            exitCode: 0,
            durationSeconds: 0,
            standardOutput: large,
            standardError: ""
        )
        let truncated = input.truncatedStandardOutput
        #expect(truncated.hasPrefix("[truncated"))
        #expect(truncated.count <= RunSummaryInput.maxBufferBytes + 64)
    }

    // MARK: Snapshot archive round-trip

    @Test func runOutcomeDTORoundTripsAISummaryFields() throws {
        let original = RunOutcomeRecord(providerID: "openai.codex")
        let summary = RunSummary(
            filesChanged: ["A.swift"],
            testsPassed: 5,
            testsFailed: 1,
            oneLineDescription: "Added A.",
            suggestedAccuracyRating: .minorFixNeeded
        )
        let stamped = Date(timeIntervalSince1970: 1_750_000_500)
        original.applyRunSummary(summary, generatedAt: stamped)

        let dto = RunOutcomeDTO(from: original)
        let copy = dto.makeRecord()

        #expect(copy.aiOneLineDescription == "Added A.")
        #expect(copy.aiTestsPassed == 5)
        #expect(copy.aiTestsFailed == 1)
        #expect(copy.aiSuggestedAccuracyRating == AccuracyRating.minorFixNeeded.rawValue)
        #expect(copy.aiSummaryGeneratedAt == stamped)
        #expect(copy.aiFilesChanged == ["A.swift"])

        // Codable round-trip through JSON also preserves the additive fields
        // so older archives written before Phase 7.2 stay decodable.
        let encoded = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(RunOutcomeDTO.self, from: encoded)
        #expect(decoded.aiOneLineDescription == dto.aiOneLineDescription)
        #expect(decoded.aiSuggestedAccuracyRating == dto.aiSuggestedAccuracyRating)
        #expect(decoded.aiFilesChangedJSON == dto.aiFilesChangedJSON)
    }

    // MARK: Dispatcher integration

    @Test func dispatcherStampsSummaryOnSuccessfulRun() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let scriptedSummary = RunSummary(
            filesChanged: ["Services/RunSummary.swift"],
            testsPassed: nil,
            testsFailed: nil,
            oneLineDescription: "Added the run-summary scaffolding.",
            suggestedAccuracyRating: .correct
        )
        let summarizer = ScriptedRunSummarizer(constant: scriptedSummary)
        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout("touched Services/RunSummary.swift"),
            .stdout("Compile succeeded."),
            .finished(exitCode: 0),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner, summarizer: summarizer)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()
        await Self.awaitSummary(dispatcher)

        #expect(dispatcher.status == .succeeded)
        switch dispatcher.aiSummaryStatus {
        case .succeeded(let summary):
            #expect(summary == scriptedSummary)
        default:
            Issue.record("Expected .succeeded, got \(dispatcher.aiSummaryStatus)")
        }

        let outcome = try #require(try context.fetch(FetchDescriptor<RunOutcomeRecord>()).first)
        #expect(outcome.aiOneLineDescription == "Added the run-summary scaffolding.")
        #expect(outcome.aiSuggestedAccuracyRating == AccuracyRating.correct.rawValue)
        #expect(outcome.aiSummaryGeneratedAt != nil)
        // Manual rating is still unrated until the user picks one — the AI
        // suggestion never overwrites the user's explicit rating.
        #expect(outcome.accuracyRating == AccuracyRating.unrated.rawValue)
    }

    @Test func dispatcherSummarizerErrorDoesNotDegradeRunOutcome() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        struct BoomError: Error, LocalizedError {
            var errorDescription: String? { "model refused" }
        }
        let summarizer = ScriptedRunSummarizer(throwing: RunSummaryError.generationFailed("model refused"))
        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout("done"),
            .finished(exitCode: 0),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner, summarizer: summarizer)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()
        await Self.awaitSummary(dispatcher)

        // Run itself is still succeeded; AI summary status is .failed.
        #expect(dispatcher.status == .succeeded)
        switch dispatcher.aiSummaryStatus {
        case .failed(let reason):
            #expect(reason.contains("model refused"))
        default:
            Issue.record("Expected .failed, got \(dispatcher.aiSummaryStatus)")
        }

        let outcome = try #require(try context.fetch(FetchDescriptor<RunOutcomeRecord>()).first)
        #expect(outcome.status == RunStatus.succeeded.rawValue)
        // Nothing was stamped because summarisation failed.
        #expect(outcome.aiSummaryGeneratedAt == nil)
        #expect(outcome.aiOneLineDescription == nil)
    }

    @Test func dispatcherSummarizerUnavailableSurfacesUnavailableStatus() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let summarizer = NoopRunSummarizer(reason: "Apple Intelligence is off in test host.")
        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout("ran"),
            .finished(exitCode: 0),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner, summarizer: summarizer)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()
        await Self.awaitSummary(dispatcher)

        switch dispatcher.aiSummaryStatus {
        case .unavailable(let reason):
            #expect(reason.lowercased().contains("apple intelligence"))
        default:
            Issue.record("Expected .unavailable, got \(dispatcher.aiSummaryStatus)")
        }
    }

    @Test func failedRunDoesNotInvokeSummarizer() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        actor InvocationCounter {
            private(set) var calls = 0
            func record() { calls += 1 }
            func value() -> Int { calls }
        }
        let counter = InvocationCounter()
        let summarizer = ScriptedRunSummarizer { _ in
            await counter.record()
            return RunSummary(oneLineDescription: "should not happen", suggestedAccuracyRating: .correct)
        }

        let runner = ScriptedAgentProcessRunner(steps: [
            .stderr("boom"),
            .finished(exitCode: 1),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner, summarizer: summarizer)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()

        #expect(dispatcher.status == .failed)
        // Give a tiny grace window so any stray task would have run.
        try? await Task.sleep(nanoseconds: 30_000_000)
        let calls = await counter.value()
        #expect(calls == 0)
        #expect(dispatcher.aiSummaryStatus == .notRequested)
    }

    @Test func dispatcherForwardsCapturedBuffersToSummarizer() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        actor InputCapture {
            private var lastInput: RunSummaryInput?
            func set(_ input: RunSummaryInput) { lastInput = input }
            func get() -> RunSummaryInput? { lastInput }
        }
        let capture = InputCapture()
        let summarizer = ScriptedRunSummarizer { input in
            await capture.set(input)
            return RunSummary(
                filesChanged: [],
                testsPassed: nil,
                testsFailed: nil,
                oneLineDescription: "ok",
                suggestedAccuracyRating: .correct
            )
        }

        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout("first stdout line"),
            .stderr("first stderr line"),
            .stdout("second stdout line"),
            .finished(exitCode: 0),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner, summarizer: summarizer)

        dispatcher.dispatch(plan: Self.makePlan(prompt: "Capture buffers test"), modelContext: context)
        await dispatcher.awaitTermination()
        await Self.awaitSummary(dispatcher)

        let captured = await capture.get()
        let input = try #require(captured)
        #expect(input.prompt == "Capture buffers test")
        #expect(input.providerID == "openai.codex")
        #expect(input.standardOutput.contains("first stdout line"))
        #expect(input.standardOutput.contains("second stdout line"))
        #expect(input.standardError.contains("first stderr line"))
        #expect(input.exitCode == 0)
    }
}
