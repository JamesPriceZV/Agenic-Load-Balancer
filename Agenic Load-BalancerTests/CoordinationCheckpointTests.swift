//
//  CoordinationCheckpointTests.swift
//  Agenic Load-BalancerTests
//
//  Created by Claude on 5/5/26.
//
//  Phase 6: tests for the AgentNotes reconciliation pipeline (NSFileCoordinator
//  wrapped read/write, reconcile state machine, preflight excerpt) and the
//  git checkpoint dispatcher path (StubGitCheckpoint result threading).
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@MainActor
@Suite("Coordination & checkpoint pipeline")
struct CoordinationCheckpointTests {
    // MARK: Helpers

    private static func makeTempProjectDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgenicCoordinationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func sampleEvent() -> CoordinationEventSnapshot {
        CoordinationEventSnapshot(
            identifier: UUID().uuidString,
            projectID: nil,
            phase: "Phase 6",
            wave: "Tests",
            step: "Sample",
            assignee: "Claude",
            status: CoordinationStatus.claimed.rawValue,
            title: "Sample work",
            detail: "Verifying reconciliation",
            relatedRunID: nil,
            commitSHA: nil,
            conflictMarker: nil,
            createdAt: Date(timeIntervalSince1970: 100_000)
        )
    }

    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CheckpointTests-\(UUID().uuidString)",
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    private static func makePlan(rootPath: String) -> RunPlan {
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
            mode: .commitPushCheckpoint,
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
            prompt: "Implement checkpoint",
            projectID: "proj-1",
            projectName: "TestProj",
            projectRootPath: rootPath,
            mode: .commitPushCheckpoint,
            score: score,
            promptExcerptSyncEnabled: false
        )
    }

    private struct StubExecutableResolver: CLIExecutableResolving {
        let resolvedPath: String?
        let version: String?
        func resolveExecutable(named binaryName: String) -> String? { resolvedPath }
        func versionString(executablePath: String) async -> String? { version }
    }

    // MARK: AgentNotes reconciliation

    @Test func ensureAgentNotesCreatesFileViaCoordinatedWrite() async throws {
        let url = try Self.makeTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: url) }

        let actor = ProjectCoordinationActor()
        let result = try await actor.ensureAgentNotes(
            projectName: "Demo",
            rootPath: url.path,
            events: [Self.sampleEvent()]
        )
        #expect(result.created)
        #expect(FileManager.default.fileExists(atPath: result.fileURL.path))
        let contents = try String(contentsOf: result.fileURL, encoding: .utf8)
        #expect(contents.contains("AgentNotes.md"))
        #expect(contents.contains("Sample work"))
    }

    @Test func reconcileReturnsFileMissingWhenAbsent() async throws {
        let url = try Self.makeTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        let actor = ProjectCoordinationActor()

        let reconciliation = try await actor.reconcile(
            projectName: "Demo",
            rootPath: url.path,
            events: []
        )
        if case .fileMissing = reconciliation.state {
            #expect(reconciliation.suggestedContent.contains("AgentNotes.md"))
        } else {
            Issue.record("Expected .fileMissing, got \(reconciliation.state)")
        }
    }

    @Test func reconcileReturnsFileMatchesAfterEnsure() async throws {
        let url = try Self.makeTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: url) }

        let actor = ProjectCoordinationActor()
        _ = try await actor.ensureAgentNotes(
            projectName: "Demo",
            rootPath: url.path,
            events: [Self.sampleEvent()]
        )
        let reconciliation = try await actor.reconcile(
            projectName: "Demo",
            rootPath: url.path,
            events: [Self.sampleEvent()]
        )
        if case .fileMatches = reconciliation.state {
            // expected
        } else {
            Issue.record("Expected .fileMatches after ensure, got \(reconciliation.state)")
        }
    }

    @Test func reconcileDetectsConflictMarkers() async throws {
        let url = try Self.makeTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        let fileURL = url.appendingPathComponent("AgentNotes.md")
        let conflicted = """
        # AgentNotes.md
        <<<<<<< HEAD
        Active claims
        =======
        Other claims
        >>>>>>> branch
        """
        try conflicted.write(to: fileURL, atomically: true, encoding: .utf8)

        let actor = ProjectCoordinationActor()
        let reconciliation = try await actor.reconcile(
            projectName: "Demo",
            rootPath: url.path,
            events: []
        )
        if case .conflictMarkers = reconciliation.state {
            #expect(reconciliation.requiresAttention)
        } else {
            Issue.record("Expected .conflictMarkers, got \(reconciliation.state)")
        }
    }

    @Test func reconcileReportsDivergenceWithChecksums() async throws {
        let url = try Self.makeTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        let fileURL = url.appendingPathComponent("AgentNotes.md")
        try "# Hand-edited\nNot the same content at all.".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        let actor = ProjectCoordinationActor()
        let reconciliation = try await actor.reconcile(
            projectName: "Demo",
            rootPath: url.path,
            events: [Self.sampleEvent()]
        )
        if case let .fileDiverged(local, generated) = reconciliation.state {
            #expect(local != generated)
            #expect(local.count == 64) // SHA-256 hex length
            #expect(generated.count == 64)
        } else {
            Issue.record("Expected .fileDiverged, got \(reconciliation.state)")
        }
    }

    @Test func applyReconciliationOverwritesFile() async throws {
        let url = try Self.makeTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        let fileURL = url.appendingPathComponent("AgentNotes.md")
        try "stale".write(to: fileURL, atomically: true, encoding: .utf8)

        let actor = ProjectCoordinationActor()
        let suggested = try await actor.reconcile(
            projectName: "Demo",
            rootPath: url.path,
            events: [Self.sampleEvent()]
        ).suggestedContent

        let result = try await actor.applyReconciliation(
            rootPath: url.path,
            suggestedContent: suggested
        )
        #expect(!result.created) // file already existed
        let updated = try String(contentsOf: result.fileURL, encoding: .utf8)
        #expect(updated == suggested)
    }

    @Test func readAgentNotesExcerptReturnsNilWhenMissing() async throws {
        let url = try Self.makeTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        let actor = ProjectCoordinationActor()
        let excerpt = await actor.readAgentNotesExcerpt(rootPath: url.path)
        #expect(excerpt == nil)
    }

    @Test func readAgentNotesExcerptReturnsContentWhenPresent() async throws {
        let url = try Self.makeTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        let fileURL = url.appendingPathComponent("AgentNotes.md")
        try "# Hello\nClaim: foo".write(to: fileURL, atomically: true, encoding: .utf8)

        let actor = ProjectCoordinationActor()
        let excerpt = await actor.readAgentNotesExcerpt(rootPath: url.path)
        #expect(excerpt?.contains("Claim: foo") == true)
    }

    // MARK: composeCommandPrompt

    @Test func composeCommandPromptInjectsExcerptAboveUserPrompt() {
        let composed = RunDispatcher.composeCommandPrompt(
            userPrompt: "Implement X",
            agentNotesExcerpt: "Active: do not touch /Sources/Auth"
        )
        #expect(composed.contains("Active: do not touch /Sources/Auth"))
        #expect(composed.contains("Implement X"))
        // The user prompt comes after the excerpt.
        let excerptRange = composed.range(of: "Active:")!
        let promptRange = composed.range(of: "Implement X")!
        #expect(excerptRange.lowerBound < promptRange.lowerBound)
    }

    @Test func composeCommandPromptOmitsBlockWhenNoExcerpt() {
        let composed = RunDispatcher.composeCommandPrompt(
            userPrompt: "Just the prompt",
            agentNotesExcerpt: nil
        )
        #expect(composed == "Just the prompt")
    }

    // MARK: Git checkpoint dispatch

    @Test func successfulCheckpointStampsCommitSHA() async throws {
        let projectDir = try Self.makeTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: projectDir) }
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(steps: [
            .stdout("doing work"),
            .finished(exitCode: 0),
        ])
        let factory: @Sendable (String, ProviderCommandProfileSnapshot?) -> AgentCLIAdapter = { id, profile in
            GenericCLIAdapter(
                providerID: id,
                commandProfile: profile,
                executableResolver: StubExecutableResolver(resolvedPath: "/usr/local/bin/codex", version: "1.0")
            )
        }
        let stub = StubGitCheckpoint(behavior: .succeed(sha: "abcdef1234567890", pushed: true))
        let dispatcher = RunDispatcher(
            runner: runner,
            adapterFactory: factory,
            gitCheckpoint: stub
        )

        dispatcher.dispatch(
            plan: Self.makePlan(rootPath: projectDir.path),
            modelContext: context
        )
        await dispatcher.awaitTermination()
        // Allow the post-success checkpoint Task to run.
        try? await Task.sleep(nanoseconds: 50_000_000)

        switch dispatcher.checkpointStatus {
        case .succeeded(let sha, let pushed, _):
            #expect(sha == "abcdef1234567890")
            #expect(pushed == true)
        default:
            Issue.record("Expected .succeeded, got \(dispatcher.checkpointStatus)")
        }

        let outcomes = try context.fetch(FetchDescriptor<RunOutcomeRecord>())
        #expect(outcomes.first?.commitSHA == "abcdef1234567890")
        let coordination = try context.fetch(FetchDescriptor<CoordinationEventRecord>())
        #expect(coordination.contains { $0.commitSHA == "abcdef1234567890" })
    }

    @Test func nothingToCommitSurfacesCorrectly() async throws {
        let projectDir = try Self.makeTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: projectDir) }
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(steps: [.finished(exitCode: 0)])
        let factory: @Sendable (String, ProviderCommandProfileSnapshot?) -> AgentCLIAdapter = { id, profile in
            GenericCLIAdapter(
                providerID: id,
                commandProfile: profile,
                executableResolver: StubExecutableResolver(resolvedPath: "/usr/local/bin/codex", version: "1.0")
            )
        }
        let stub = StubGitCheckpoint(behavior: .fail(.nothingToCommit))
        let dispatcher = RunDispatcher(
            runner: runner,
            adapterFactory: factory,
            gitCheckpoint: stub
        )

        dispatcher.dispatch(
            plan: Self.makePlan(rootPath: projectDir.path),
            modelContext: context
        )
        await dispatcher.awaitTermination()
        try? await Task.sleep(nanoseconds: 50_000_000)

        if case .nothingToCommit = dispatcher.checkpointStatus {
            // expected
        } else {
            Issue.record("Expected .nothingToCommit, got \(dispatcher.checkpointStatus)")
        }
    }

    @Test func failedRunSkipsCheckpoint() async throws {
        let projectDir = try Self.makeTempProjectDirectory()
        defer { try? FileManager.default.removeItem(at: projectDir) }
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let runner = ScriptedAgentProcessRunner(steps: [
            .stderr("oh no"),
            .finished(exitCode: 99),
        ])
        let factory: @Sendable (String, ProviderCommandProfileSnapshot?) -> AgentCLIAdapter = { id, profile in
            GenericCLIAdapter(
                providerID: id,
                commandProfile: profile,
                executableResolver: StubExecutableResolver(resolvedPath: "/usr/local/bin/codex", version: "1.0")
            )
        }
        let stub = StubGitCheckpoint(behavior: .succeed(sha: "shouldnotappear", pushed: true))
        let dispatcher = RunDispatcher(
            runner: runner,
            adapterFactory: factory,
            gitCheckpoint: stub
        )

        dispatcher.dispatch(
            plan: Self.makePlan(rootPath: projectDir.path),
            modelContext: context
        )
        await dispatcher.awaitTermination()
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Run failed, so checkpoint should not have happened.
        #expect(dispatcher.checkpointStatus == .notRequested)
        let outcomes = try context.fetch(FetchDescriptor<RunOutcomeRecord>())
        #expect(outcomes.first?.commitSHA == nil)
    }
}
