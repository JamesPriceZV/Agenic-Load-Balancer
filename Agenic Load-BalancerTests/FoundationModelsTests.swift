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
