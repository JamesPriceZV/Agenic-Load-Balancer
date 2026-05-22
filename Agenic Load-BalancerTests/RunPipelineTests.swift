//
//  RunPipelineTests.swift
//  Agenic Load-BalancerTests
//
//  Created by OpenAI Codex on 5/5/26.
//
//  Phase 2: end-to-end tests for the run dispatch pipeline. These tests
//  exercise the dispatcher with a `ScriptedAgentProcessRunner` and a
//  stubbed CLI resolver so they never spawn a real Process.
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@MainActor
@Suite("Run pipeline")
struct RunPipelineTests {
    // MARK: Helpers

    private struct StubExecutableResolver: CLIExecutableResolving {
        let resolvedPath: String?
        let version: String?

        func resolveExecutable(named binaryName: String) -> String? { resolvedPath }
        func versionString(executablePath: String) async -> String? { version }
    }

    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "RunPipelineTests-\(UUID().uuidString)",
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    private final class CommandCaptureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedCommand: AgentCommand?

        var command: AgentCommand? {
            lock.withLock { storedCommand }
        }

        func set(_ command: AgentCommand) {
            lock.withLock {
                storedCommand = command
            }
        }
    }

    private struct CapturingRunner: AgentRunning {
        let capture: CommandCaptureBox
        let steps: [ScriptedAgentProcessRunner.Step]

        func stream(command: AgentCommand) -> AsyncThrowingStream<AgentProcessEvent, Error> {
            capture.set(command)
            return ScriptedAgentProcessRunner(steps: steps).stream(command: command)
        }
    }

    private static func makePlan(
        prompt: String = "Implement the dashboard heatmap.",
        contextCompactionEnabled: Bool = true,
        contextCompactionThresholdTokens: Int = 120_000
    ) -> RunPlan {
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
            totalScore: 0.85,
            availabilityScore: 1,
            capabilityScore: 0.9,
            limitScore: 0.8,
            accuracyScore: 0.9,
            speedScore: 0.7,
            costScore: 0.85,
            rationale: "Test plan",
            estimatedCostUSD: 0.012,
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
            promptExcerptSyncEnabled: false,
            contextCompactionEnabled: contextCompactionEnabled,
            contextCompactionThresholdTokens: contextCompactionThresholdTokens
        )
    }

    private static func makeDispatcher(
        runner: AgentRunning,
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
            summarizer: NoopRunSummarizer(reason: "RunPipelineTests do not invoke live Foundation Models.")
        )
    }

    // MARK: Tests

    @Test func missingExecutableProducesFailedOutcome() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let dispatcher = Self.makeDispatcher(
            runner: ScriptedAgentProcessRunner(steps: [.finished(exitCode: 0)]),
            resolverPath: nil
        )

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()

        #expect(dispatcher.status == .failed)
        #expect(dispatcher.lastError?.contains("codex") == true)

        let outcomes = try context.fetch(FetchDescriptor<RunOutcomeRecord>())
        #expect(outcomes.count == 1)
        #expect(outcomes.first?.status == RunStatus.failed.rawValue)

        let coordination = try context.fetch(FetchDescriptor<CoordinationEventRecord>())
        #expect(coordination.contains { $0.status == CoordinationStatus.blocked.rawValue })
    }

    @Test func missingAuthYieldsFailureWithStderrCaptured() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(steps: [
            .stderr("Error: missing authentication. Run `codex login`."),
            .finished(exitCode: 401),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()

        #expect(dispatcher.status == .failed)
        #expect(dispatcher.exitCode == 401)
        #expect(dispatcher.logs.contains { $0.kind == .stderr && $0.text.contains("missing authentication") })

        let outcomes = try context.fetch(FetchDescriptor<RunOutcomeRecord>())
        let outcome = try #require(outcomes.first { $0.status == RunStatus.failed.rawValue })
        #expect(outcome.buildResult == "exit401")
    }

    @Test func quotaExhaustionIsRecordedAsFailedRun() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout("Probing quotas…"),
            .stderr("Error: quota exceeded for provider plan."),
            .finished(exitCode: 429),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()

        #expect(dispatcher.status == .failed)
        #expect(dispatcher.exitCode == 429)

        let usage = try context.fetch(FetchDescriptor<UsageLedgerEntry>())
        #expect(usage.count == 1)
        let entry = try #require(usage.first)
        #expect(entry.durationSeconds >= 0)

        let coordination = try context.fetch(FetchDescriptor<CoordinationEventRecord>())
        #expect(coordination.contains { $0.status == CoordinationStatus.conflict.rawValue })
    }

    @Test func contextWindowFailureWithZeroExitIsRecordedAsFailedRun() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout("Provider error: request exceeded the available context window."),
            .finished(exitCode: 0),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()

        #expect(dispatcher.status == .failed)
        #expect(dispatcher.exitCode == 0)
        #expect(dispatcher.lastError?.contains("context window") == true)

        let outcome = try #require(try context.fetch(FetchDescriptor<RunOutcomeRecord>()).first)
        #expect(outcome.status == RunStatus.failed.rawValue)
        #expect(outcome.buildResult == "exit0")
    }

    @Test func nestedNonZeroExitCodeWithZeroProcessExitIsRecordedAsFailedRun() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout(#"{"type":"tool_result","exit_code":2,"status":"completed"}"#),
            .finished(exitCode: 0),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()

        #expect(dispatcher.status == .failed)
        #expect(dispatcher.lastError?.contains("exit code 2") == true)

        let coordination = try context.fetch(FetchDescriptor<CoordinationEventRecord>())
        #expect(coordination.contains { $0.status == CoordinationStatus.conflict.rawValue })
    }

    @Test func malformedOutputStillCompletesAsSucceeded() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout("@@@@@ malformed not-json output @@@@@"),
            .stdout(#"{"partial":"json"  // no closing brace"#),
            .finished(exitCode: 0),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()

        #expect(dispatcher.status == .succeeded)
        #expect(dispatcher.exitCode == 0)
        #expect(dispatcher.logs.contains { $0.text.contains("malformed") })
    }

    @Test func tokenMarkersAreCapturedFromStream() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout("Working…"),
            .stdout(#"{"usage":{"prompt_tokens": 420, "completion_tokens": 110}}"#),
            .finished(exitCode: 0),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()

        #expect(dispatcher.status == .succeeded)
        #expect(dispatcher.promptTokens == 420)
        #expect(dispatcher.completionTokens == 110)

        let usage = try #require(try context.fetch(FetchDescriptor<UsageLedgerEntry>()).first)
        #expect(usage.promptTokens == 420)
        #expect(usage.completionTokens == 110)
    }

    @Test func codexUsagePayloadCapturesInputOutputCachedAndReasoningTokens() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout(#"{"type":"turn.completed","usage":{"input_tokens":5227767,"cached_input_tokens":4986496,"output_tokens":17603,"reasoning_output_tokens":6012}}"#),
            .finished(exitCode: 0),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()

        #expect(dispatcher.status == .succeeded)
        #expect(dispatcher.promptTokens == 5_227_767)
        #expect(dispatcher.completionTokens == 17_603)
        #expect(dispatcher.cachedPromptTokens == 4_986_496)
        #expect(dispatcher.reasoningTokens == 6_012)

        let usage = try #require(try context.fetch(FetchDescriptor<UsageLedgerEntry>()).first)
        #expect(usage.promptTokens == 5_227_767)
        #expect(usage.completionTokens == 17_603)
        #expect(usage.cachedPromptTokens == 4_986_496)
        #expect(usage.reasoningTokens == 6_012)
        #expect(usage.preprocessingSeconds >= 0)
    }

    @Test func oversizedPreflightContextIsCompactedBeforeDispatch() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let capture = CommandCaptureBox()
        let runner = CapturingRunner(capture: capture, steps: [.finished(exitCode: 0)])
        let dispatcher = Self.makeDispatcher(runner: runner)
        let notes = """
        start-active-claim
        \(String(repeating: "middle historical coordination line\n", count: 600))
        tail-active-claim
        """

        dispatcher.dispatch(
            plan: Self.makePlan(
                prompt: "Review the current implementation.",
                contextCompactionThresholdTokens: 1_200
            ),
            agentNotesExcerpt: notes,
            modelContext: context
        )
        await dispatcher.awaitTermination()

        let stdin = try #require(capture.command?.standardInput)
        #expect(stdin.contains("[compacted AgentNotes preflight"))
        #expect(stdin.contains("tail-active-claim"))
        #expect(dispatcher.preflightTokenEstimate?.totalInputTokens ?? 0 <= 1_200)

        let usage = try #require(try context.fetch(FetchDescriptor<UsageLedgerEntry>()).first)
        #expect(usage.limitWindow.contains("context:"))
    }

    @Test func contextWindowFailureStoresContinuationPromptAndTranscriptSegments() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout("Started analysis."),
            .stdout(String(repeating: "large transcript line\n", count: 260)),
            .stderr("Provider error: exceeded the available context window."),
            .finished(exitCode: 0),
        ])
        let dispatcher = Self.makeDispatcher(runner: runner)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()

        #expect(dispatcher.status == .failed)
        let outcome = try #require(try context.fetch(FetchDescriptor<RunOutcomeRecord>()).first)
        #expect(outcome.continuationPrompt?.contains("Continue the previous") == true)
        #expect(outcome.continuationSummary?.contains("context window") == true)
        #expect(outcome.transcriptSegmentCount > 0)

        let segments = try context.fetch(FetchDescriptor<RunTranscriptSegmentRecord>())
        #expect(!segments.isEmpty)
        #expect(segments.first?.tokenEstimate ?? 0 > 0)
    }

    @Test func successfulRunCapturesDurationAndOutcomeStatus() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(
            steps: [
                .stdout("starting"),
                .stdout("done"),
                .finished(exitCode: 0),
            ],
            perStepDelayNanoseconds: 5_000_000 // 5 ms
        )
        let dispatcher = Self.makeDispatcher(runner: runner)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        await dispatcher.awaitTermination()

        #expect(dispatcher.status == .succeeded)
        let outcome = try #require(try context.fetch(FetchDescriptor<RunOutcomeRecord>()).first)
        #expect(outcome.status == RunStatus.succeeded.rawValue)
        #expect(outcome.durationSeconds >= 0)
        #expect(outcome.endedAt != nil)
    }

    @Test func processRunnerDeliversStandardInput() async throws {
        let command = AgentCommand(
            providerID: "test.stdin",
            executablePath: "/bin/cat",
            arguments: [],
            standardInput: "hello from stdin\n"
        )
        let runner = AgentProcessRunner()
        var stdout: [String] = []
        var finishedCode: Int32?

        for try await event in runner.stream(command: command) {
            switch event {
            case .started:
                break
            case .standardOutput(let line):
                stdout.append(line)
            case .standardError:
                break
            case .finished(let code):
                finishedCode = code
            }
        }

        #expect(stdout == ["hello from stdin"])
        #expect(finishedCode == 0)
    }

    @Test func userCancellationTransitionsToCancelled() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        // Long delay between steps so the cancel arrives before the script finishes.
        let runner = ScriptedAgentProcessRunner(
            steps: [
                .stdout("step 1"),
                .stdout("step 2"),
                .stdout("step 3"),
                .finished(exitCode: 0),
            ],
            perStepDelayNanoseconds: 200_000_000 // 200 ms per step
        )
        let dispatcher = Self.makeDispatcher(runner: runner)

        dispatcher.dispatch(plan: Self.makePlan(), modelContext: context)
        // Wait long enough for the run to enter `.running`, then cancel.
        try? await Task.sleep(nanoseconds: 50_000_000)
        dispatcher.cancel()
        await dispatcher.awaitTermination(timeout: 3.0)

        #expect(dispatcher.status == .cancelled)
        let outcome = try #require(try context.fetch(FetchDescriptor<RunOutcomeRecord>()).first)
        #expect(outcome.status == RunStatus.cancelled.rawValue)
        let coordination = try #require(try context.fetch(FetchDescriptor<CoordinationEventRecord>()).first)
        #expect(coordination.status == CoordinationStatus.cancelled.rawValue)
        #expect(coordination.conflictMarker == nil)
    }
}
