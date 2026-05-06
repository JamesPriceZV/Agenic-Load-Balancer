//
//  FoundationModelsTests.swift
//  Agenic Load-BalancerTests
//
//  Created by Claude on 5/5/26.
//
//  Phase 7.1: tests for the Foundation Models adapter, the composite
//  runner's dispatch logic, the catalog/quota registration, and the shared
//  AgentAdapterFactory. The actual `LanguageModelSession` invocation is not
//  exercised here because it depends on Apple Intelligence being enabled
//  on the host — production code degrades gracefully via the availability
//  checker, which we exercise with a stub.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@MainActor
@Suite("Foundation Models integration")
struct FoundationModelsTests {
    private static func snapshot() -> AgentProviderSnapshot {
        guard let draft = ProviderCatalog.defaultProfiles.first(where: { $0.identifier == "apple.foundation-models" }) else {
            preconditionFailure("apple.foundation-models missing from ProviderCatalog")
        }
        return AgentProviderSnapshot(
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
    }

    // MARK: Catalog & quota

    @Test func catalogIncludesAppleFoundationModels() {
        let providerIDs = Set(ProviderCatalog.defaultProfiles.map(\.identifier))
        #expect(providerIDs.contains("apple.foundation-models"))
    }

    @Test func usageLimitPolicyHasFoundationModelsQuota() {
        let policy = UsageLimitPolicy.default
        let quota = policy.quota(forProvider: "apple.foundation-models")
        #expect(quota.providerID == "apple.foundation-models")
        #expect(quota.softCostBudgetUSD == 0)
        #expect(quota.refreshWindow == .rollingTwentyFourHours)
        #expect(quota.maxCallsPerWindow > 1_000)
    }

    @Test func adapterFactoryReturnsFoundationModelsAdapterForCatalogID() {
        let adapter = AgentAdapterFactory.makeAdapter(providerID: "apple.foundation-models")
        #expect(adapter is FoundationModelsAdapter)
        let other = AgentAdapterFactory.makeAdapter(providerID: "openai.codex")
        #expect(other is GenericCLIAdapter)
    }

    // MARK: Adapter

    @Test func adapterBuildCommandUsesInProcessExecutablePath() throws {
        let provider = Self.snapshot()
        let adapter = FoundationModelsAdapter(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available)
        )
        let command = try adapter.buildCommand(
            prompt: "Implement the heatmap.",
            projectPath: "/tmp/proj",
            mode: .implementation,
            provider: provider
        )
        #expect(command.executablePath == FoundationModelsAdapter.inProcessExecutablePath)
        #expect(command.workingDirectory == "/tmp/proj")
        // The catalog wraps the user prompt in the coordination preamble.
        let lastArg = try #require(command.arguments.last)
        #expect(lastArg.contains("Implement the heatmap."))
        #expect(lastArg.contains("AgentNotes"))
    }

    @Test func adapterBuildCommandRejectsUnsupportedMode() {
        let draft = ProviderCatalog.defaultProfiles.first { $0.identifier == "apple.foundation-models" }!
        // Synthesize a snapshot with no supported modes to verify rejection.
        let limited = AgentProviderSnapshot(
            identifier: draft.identifier,
            displayName: draft.displayName,
            binaryName: draft.binaryName,
            installCommand: draft.installCommand,
            verificationCommand: draft.verificationCommand,
            supportedExecutionModes: AgentExecutionMode.recommendOnly.rawValue,
            capabilities: draft.capabilities,
            installedState: .available,
            authState: .authenticated,
            isEnabled: true
        )
        let adapter = FoundationModelsAdapter(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available)
        )
        do {
            _ = try adapter.buildCommand(
                prompt: "x",
                projectPath: nil,
                mode: .commitPushCheckpoint,
                provider: limited
            )
            Issue.record("Expected unsupported-mode error, got success.")
        } catch let error as AgentProcessError {
            switch error {
            case .invalidCommand(let message):
                #expect(message.contains("does not support"))
            default:
                Issue.record("Expected .invalidCommand, got \(error)")
            }
        } catch {
            Issue.record("Expected AgentProcessError, got \(error)")
        }
    }

    @Test func adapterAvailabilityHonoursStub() async {
        let provider = Self.snapshot()

        let availableAdapter = FoundationModelsAdapter(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available)
        )
        let availableSnapshot = await availableAdapter.availability(for: provider)
        #expect(availableSnapshot.availabilityState == .available)
        #expect(availableSnapshot.detectedVersion?.contains("on-device") == true)

        let notEnabledAdapter = FoundationModelsAdapter(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.appleIntelligenceNotEnabled)
        )
        let notEnabled = await notEnabledAdapter.availability(for: provider)
        #expect(notEnabled.availabilityState == .missing)
        #expect(notEnabled.message.lowercased().contains("apple intelligence"))

        let modelNotReadyAdapter = FoundationModelsAdapter(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.modelNotReady)
        )
        let notReady = await modelNotReadyAdapter.availability(for: provider)
        #expect(notReady.availabilityState == .unknown)
    }

    @Test func adapterAvailabilitySkipsForDisabledProvider() async {
        // The catalog draft's fields are `let` bindings so we can't mutate
        // them; instead, synthesize a disabled snapshot directly.
        let provider = AgentProviderSnapshot(
            identifier: "apple.foundation-models",
            displayName: "Apple Foundation Models",
            binaryName: "in-process",
            installCommand: "",
            verificationCommand: "",
            supportedExecutionModes: AgentExecutionMode.recommendOnly.rawValue,
            capabilities: "",
            installedState: .available,
            authState: .authenticated,
            isEnabled: false
        )
        let adapter = FoundationModelsAdapter(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available)
        )
        let snapshot = await adapter.availability(for: provider)
        #expect(snapshot.availabilityState == .disabled)
    }

    // MARK: Runner unavailability path

    @Test func runnerEmitsErrorAndExits78WhenUnavailable() async throws {
        let runner = FoundationModelsRunner(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.appleIntelligenceNotEnabled)
        )
        let command = AgentCommand(
            providerID: "apple.foundation-models",
            executablePath: FoundationModelsAdapter.inProcessExecutablePath,
            arguments: ["test prompt"]
        )
        var sawStarted = false
        var stderrText = ""
        var exitCode: Int32?
        for try await event in runner.stream(command: command) {
            switch event {
            case .started: sawStarted = true
            case .standardOutput: break
            case .standardError(let line): stderrText += line
            case .finished(let code): exitCode = code
            }
        }
        #expect(sawStarted)
        #expect(stderrText.lowercased().contains("apple intelligence"))
        #expect(exitCode == 78)
    }

    // MARK: Composite runner dispatch

    @Test func compositeRunnerRoutesInProcessCommandsToFoundationModelsRunner() async throws {
        let processSteps = ScriptedAgentProcessRunner(steps: [
            .stdout("from process"),
            .finished(exitCode: 0),
        ])
        let fmSteps = ScriptedAgentProcessRunner(steps: [
            .stdout("from foundation models"),
            .finished(exitCode: 0),
        ])
        let composite = CompositeAgentRunner(
            processRunner: processSteps,
            foundationModelsRunner: fmSteps
        )

        let inProcessCommand = AgentCommand(
            providerID: "apple.foundation-models",
            executablePath: FoundationModelsAdapter.inProcessExecutablePath,
            arguments: ["irrelevant"]
        )
        var fmOutput = ""
        for try await event in composite.stream(command: inProcessCommand) {
            if case .standardOutput(let line) = event { fmOutput += line }
        }
        #expect(fmOutput.contains("foundation models"))

        let processCommand = AgentCommand(
            providerID: "openai.codex",
            executablePath: "/usr/local/bin/codex",
            arguments: ["exec"]
        )
        var processOutput = ""
        for try await event in composite.stream(command: processCommand) {
            if case .standardOutput(let line) = event { processOutput += line }
        }
        #expect(processOutput.contains("from process"))
    }

    // MARK: Availability translation

    @Test func availabilityTranslationDescribesEachState() {
        #expect(FoundationModelsAvailability.available.isAvailable)
        #expect(!FoundationModelsAvailability.appleIntelligenceNotEnabled.isAvailable)
        #expect(!FoundationModelsAvailability.deviceNotEligible.isAvailable)
        #expect(!FoundationModelsAvailability.modelNotReady.isAvailable)
        #expect(FoundationModelsAvailability.appleIntelligenceNotEnabled.message.lowercased().contains("apple intelligence"))
        #expect(FoundationModelsAvailability.deviceNotEligible.message.lowercased().contains("eligible"))
        #expect(FoundationModelsAvailability.modelNotReady.message.lowercased().contains("ready"))
    }
}

// MARK: - Live streaming path

/// Scripted Foundation Models session driver used to exercise the runner's
/// snapshot-to-delta-to-line translation without depending on Apple
/// Intelligence being enabled on the host. Each step yields the
/// accumulated text the runner should observe for that snapshot.
private struct ScriptedFoundationModelsSessionDriver: FoundationModelsSessionDriving {
    enum Step: Sendable {
        case snapshot(String)
        case fail(any Error & Sendable)
    }

    let steps: [Step]
    let perStepDelayNanoseconds: UInt64

    init(steps: [Step], perStepDelayNanoseconds: UInt64 = 0) {
        self.steps = steps
        self.perStepDelayNanoseconds = perStepDelayNanoseconds
    }

    func streamSnapshots(prompt _: String) -> AsyncThrowingStream<String, Error> {
        let scripted = steps
        let delay = perStepDelayNanoseconds
        return AsyncThrowingStream { continuation in
            let task = Task {
                for step in scripted {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }
                    switch step {
                    case .snapshot(let value):
                        continuation.yield(value)
                    case .fail(let error):
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

private struct FoundationModelsScriptedFailure: Error, LocalizedError {
    let underlying: String
    var errorDescription: String? { underlying }
}

@MainActor
@Suite("Foundation Models live streaming path")
struct FoundationModelsStreamingTests {
    private static func makeCommand() -> AgentCommand {
        AgentCommand(
            providerID: "apple.foundation-models",
            executablePath: FoundationModelsAdapter.inProcessExecutablePath,
            arguments: ["the prompt"]
        )
    }

    @Test func runnerEmitsLineBufferedStdoutFromSnapshotDeltas() async throws {
        // The driver yields accumulated snapshots — the runner must split
        // by newline and emit only completed lines as `.standardOutput`.
        let driver = ScriptedFoundationModelsSessionDriver(steps: [
            .snapshot("Hello, "),                    // partial line, no newline yet
            .snapshot("Hello, world\n"),             // newline → emit "Hello, world"
            .snapshot("Hello, world\nDone."),        // continued; "Done." pending
        ])
        let runner = FoundationModelsRunner(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available),
            sessionDriver: driver
        )

        var stdout: [String] = []
        var exit: Int32?
        for try await event in runner.stream(command: Self.makeCommand()) {
            switch event {
            case .standardOutput(let line): stdout.append(line)
            case .finished(let code): exit = code
            default: break
            }
        }

        #expect(stdout == ["Hello, world", "Done."])
        #expect(exit == 0)
    }

    @Test func runnerEmitsHeartbeatWhenDriverProducesNoContent() async throws {
        let driver = ScriptedFoundationModelsSessionDriver(steps: [])
        let runner = FoundationModelsRunner(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available),
            sessionDriver: driver
        )

        var stdout: [String] = []
        var exit: Int32?
        for try await event in runner.stream(command: Self.makeCommand()) {
            switch event {
            case .standardOutput(let line): stdout.append(line)
            case .finished(let code): exit = code
            default: break
            }
        }

        // The runner emits a single heartbeat so the usage estimator and
        // outcome ledger see at least one stdout line for an empty session.
        #expect(stdout.count == 1)
        #expect(stdout.first?.lowercased().contains("foundation models") == true)
        #expect(exit == 0)
    }

    @Test func runnerSurfacesDriverErrorAsStderrAndNonZeroExit() async throws {
        let driver = ScriptedFoundationModelsSessionDriver(steps: [
            .snapshot("Starting work\n"),
            .fail(FoundationModelsScriptedFailure(underlying: "guard rail violation")),
        ])
        let runner = FoundationModelsRunner(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available),
            sessionDriver: driver
        )

        var stdout: [String] = []
        var stderrJoined = ""
        var exit: Int32?
        for try await event in runner.stream(command: Self.makeCommand()) {
            switch event {
            case .standardOutput(let line): stdout.append(line)
            case .standardError(let line): stderrJoined += line
            case .finished(let code): exit = code
            default: break
            }
        }

        #expect(stdout == ["Starting work"])
        #expect(stderrJoined.lowercased().contains("guard rail"))
        #expect(exit == 1)
    }

    @Test func runnerReportsFrameworkUnavailableWhenAvailableButDriverIsNil() async throws {
        // Availability says yes but no driver was injected (e.g. running on
        // a host without the FoundationModels framework). The runner must
        // emit a clear stderr line and exit 78 so the approval sheet can
        // render the failure.
        let runner = FoundationModelsRunner(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available),
            sessionDriver: nil
        )

        var stderrJoined = ""
        var exit: Int32?
        for try await event in runner.stream(command: Self.makeCommand()) {
            switch event {
            case .standardError(let line): stderrJoined += line
            case .finished(let code): exit = code
            default: break
            }
        }

        #expect(stderrJoined.lowercased().contains("framework"))
        #expect(exit == 78)
    }

    @Test func compositeRunnerWithDefaultsRoutesInProcessThroughFoundationModelsRunner() async throws {
        // When the dispatcher uses its production default
        // (`CompositeAgentRunner()`), in-process commands must reach the
        // foundation models runner. We inject a stubbed availability that
        // says `.appleIntelligenceNotEnabled` so the path completes without
        // touching real Apple Intelligence — which is the same end-to-end
        // shape we'd see in CI on a non-AI host.
        let foundationRunner = FoundationModelsRunner(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.appleIntelligenceNotEnabled),
            sessionDriver: nil
        )
        let composite = CompositeAgentRunner(
            processRunner: ScriptedAgentProcessRunner(steps: [
                .stdout("process should not run for in-process command"),
                .finished(exitCode: 0),
            ]),
            foundationModelsRunner: foundationRunner
        )

        var stderrJoined = ""
        var exit: Int32?
        for try await event in composite.stream(command: Self.makeCommand()) {
            switch event {
            case .standardError(let line): stderrJoined += line
            case .finished(let code): exit = code
            default: break
            }
        }

        #expect(stderrJoined.lowercased().contains("apple intelligence"))
        #expect(exit == 78)
    }

    @Test func runnerFlushesPendingPartialLineAtEndOfStream() async throws {
        // If the model's final snapshot ends mid-line (no trailing newline),
        // the runner must still emit that partial line so the user sees the
        // final tokens before the run terminates.
        let driver = ScriptedFoundationModelsSessionDriver(steps: [
            .snapshot("First line\nSecond line — no terminator"),
        ])
        let runner = FoundationModelsRunner(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available),
            sessionDriver: driver
        )

        var stdout: [String] = []
        for try await event in runner.stream(command: Self.makeCommand()) {
            if case .standardOutput(let line) = event { stdout.append(line) }
        }

        #expect(stdout == ["First line", "Second line — no terminator"])
    }
}
