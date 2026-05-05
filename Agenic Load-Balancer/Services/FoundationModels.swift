//
//  FoundationModels.swift
//  Agenic Load-Balancer
//
//  Created by Claude on 5/5/26.
//
//  Phase 7.1: plumbing for Apple Foundation Models as a first-class
//  provider inside the existing run pipeline. The `FoundationModelsAdapter`
//  produces an in-process `AgentCommand`; the `FoundationModelsRunner`
//  handles the command and a `CompositeAgentRunner` routes commands by
//  `executablePath` prefix so the existing approval sheet, live console,
//  accuracy ledger, dashboard, and snapshot/restore flows treat Apple
//  Intelligence exactly like any other provider.
//
//  This file intentionally does NOT import the FoundationModels framework
//  yet — the actual `LanguageModelSession.streamResponse(...)` invocation
//  ships in Phase 7.1b once we've pinned the exact macOS 26.4 SDK
//  signatures. The runner currently emits a clear "session call not yet
//  wired" stderr line so the live console explains what's happening, and
//  the approval sheet / dashboard / outcome ledger can be exercised end to
//  end without depending on Apple Intelligence being enabled on the test
//  device. The availability protocol surface is in place so swapping in
//  the real session later is purely an internal change.
//
//  Cross-cutting design rule (per memory feedback_foundation_models): every
//  Foundation Models call site must check
//  `SystemLanguageModel.default.availability` (via the protocol below) and
//  degrade gracefully when Apple Intelligence is unavailable.
//

import Foundation

/// Sendable Availability sum type that hides the Foundation Models import
/// behind a small, testable boundary. The rest of the app can depend on
/// this type even on SDKs without `FoundationModels`.
enum FoundationModelsAvailability: Sendable, Equatable {
    case available
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case frameworkUnavailable
    case unknown(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .available: "Apple Foundation Models is available on this device."
        case .appleIntelligenceNotEnabled: "Apple Intelligence is not enabled in System Settings → Apple Intelligence & Siri."
        case .deviceNotEligible: "This device is not eligible for Apple Intelligence."
        case .modelNotReady: "The on-device model is downloading or not ready yet."
        case .frameworkUnavailable: "The FoundationModels framework is not available in this build."
        case .unknown(let detail): "Unknown availability state: \(detail)"
        }
    }
}

/// Indirection so the adapter and runner don't talk to
/// `SystemLanguageModel.default` directly. Tests inject
/// `StubFoundationModelsAvailabilityChecker`; production uses
/// `SystemLanguageModelAvailabilityChecker`.
protocol FoundationModelsAvailabilityChecking: Sendable {
    func currentAvailability() -> FoundationModelsAvailability
}

/// Production checker placeholder. Phase 7.1b will replace the body with
/// `SystemLanguageModel.default.availability` once the macOS 26.4 SDK
/// surface is pinned; for now we report `.frameworkUnavailable` so the
/// runner emits a clear "not wired yet" message and the rest of the
/// pipeline behaves predictably regardless of Apple Intelligence state.
struct SystemLanguageModelAvailabilityChecker: FoundationModelsAvailabilityChecking {
    init() {}

    func currentAvailability() -> FoundationModelsAvailability {
        .frameworkUnavailable
    }
}

/// Test-friendly stub. Returns the configured value on every call.
struct StubFoundationModelsAvailabilityChecker: FoundationModelsAvailabilityChecking {
    let value: FoundationModelsAvailability

    init(_ value: FoundationModelsAvailability) {
        self.value = value
    }

    func currentAvailability() -> FoundationModelsAvailability { value }
}

/// `AgentCLIAdapter` for the in-process Apple Foundation Models provider.
/// The adapter doesn't resolve a real executable; it tags the command with
/// a sentinel `executablePath` (`in-process://foundation-models`) that the
/// `CompositeAgentRunner` routes to the `FoundationModelsRunner` instead of
/// `AgentProcessRunner`.
struct FoundationModelsAdapter: AgentCLIAdapter {
    let providerID: String = FoundationModelsAdapter.catalogProviderID
    let availabilityChecker: any FoundationModelsAvailabilityChecking

    init(availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker()) {
        self.availabilityChecker = availabilityChecker
    }

    /// Stable provider identifier matching the `ProviderCatalog` entry.
    static let catalogProviderID = "apple.foundation-models"

    /// Sentinel executable path that the composite runner uses to route
    /// commands to the in-process runner.
    static let inProcessExecutablePath = "in-process://foundation-models"

    func availability(for provider: AgentProviderSnapshot) async -> ProviderHealthSnapshot {
        guard provider.isEnabled else {
            return ProviderHealthSnapshot(
                providerID: provider.identifier,
                availabilityState: .disabled,
                detectedVersion: nil,
                message: "Provider is disabled.",
                checkedAt: Date()
            )
        }
        let state = availabilityChecker.currentAvailability()
        let mappedState: ProviderAvailabilityState
        switch state {
        case .available: mappedState = .available
        case .appleIntelligenceNotEnabled, .deviceNotEligible, .frameworkUnavailable:
            mappedState = .missing
        case .modelNotReady, .unknown:
            mappedState = .unknown
        }
        return ProviderHealthSnapshot(
            providerID: provider.identifier,
            availabilityState: mappedState,
            detectedVersion: state.isAvailable ? "Apple Foundation Models (on-device)" : nil,
            message: state.message,
            checkedAt: Date()
        )
    }

    func buildCommand(
        prompt: String,
        projectPath: String?,
        mode: AgentExecutionMode,
        provider: AgentProviderSnapshot
    ) throws -> AgentCommand {
        guard provider.supports(mode) else {
            throw AgentProcessError.invalidCommand("\(provider.displayName) does not support \(mode.label).")
        }
        let coordinationPrompt = GenericCLIAdapter.coordinationPrompt(prompt: prompt, mode: mode)
        return AgentCommand(
            providerID: provider.identifier,
            executablePath: Self.inProcessExecutablePath,
            arguments: [coordinationPrompt],
            workingDirectory: projectPath,
            requiresApproval: mode != .recommendOnly
        )
    }
}

/// Phase 7.1 runner. Currently emits a clear "session not yet wired"
/// message so the live console / outcome ledger / dashboard can exercise
/// the in-process path end to end. Phase 7.1b will replace `runSession(...)`
/// with the real `LanguageModelSession.streamResponse(...)` call once we've
/// pinned the macOS 26.4 SDK signatures (the previous attempt tripped a
/// dyld symbol-resolution failure at app launch on the test device).
struct FoundationModelsRunner: AgentRunning {
    let availabilityChecker: any FoundationModelsAvailabilityChecking

    init(
        availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker()
    ) {
        self.availabilityChecker = availabilityChecker
    }

    func stream(command: AgentCommand) -> AsyncThrowingStream<AgentProcessEvent, Error> {
        let prompt = Self.extractPrompt(from: command.arguments)
        let availability = availabilityChecker.currentAvailability()

        return AsyncThrowingStream { continuation in
            continuation.yield(.started(command: command.displayCommand))

            guard availability.isAvailable else {
                continuation.yield(.standardError("Apple Foundation Models unavailable: \(availability.message)"))
                continuation.yield(.finished(exitCode: 78)) // EX_CONFIG
                continuation.finish()
                return
            }

            // Phase 7.1b plug-in point: replace this branch with the real
            // `LanguageModelSession.streamResponse(...)` invocation. For
            // now we report that the architecture is wired but the session
            // call is not yet enabled, including a small echo of the
            // prompt so the live console proves the pipeline reached us.
            continuation.yield(.standardOutput("[Foundation Models · Phase 7.1] in-process runner reached."))
            continuation.yield(.standardOutput("Prompt size: \(prompt.count) chars"))
            continuation.yield(.standardError("LanguageModelSession invocation will land in Phase 7.1b."))
            continuation.yield(.finished(exitCode: 0))
            continuation.finish()
        }
    }

    /// The in-process command's last argument is the coordination-wrapped
    /// prompt; everything before it is metadata that the runner ignores.
    private static func extractPrompt(from arguments: [String]) -> String {
        arguments.last ?? ""
    }
}

/// Routes an `AgentCommand` to the right backend based on its
/// `executablePath`. Anything starting with `in-process://` goes to the
/// Foundation Models runner; everything else goes to the process runner.
struct CompositeAgentRunner: AgentRunning {
    let processRunner: any AgentRunning
    let foundationModelsRunner: any AgentRunning

    init(
        processRunner: any AgentRunning = AgentProcessRunner(),
        foundationModelsRunner: any AgentRunning = FoundationModelsRunner()
    ) {
        self.processRunner = processRunner
        self.foundationModelsRunner = foundationModelsRunner
    }

    func stream(command: AgentCommand) -> AsyncThrowingStream<AgentProcessEvent, Error> {
        if command.executablePath.hasPrefix("in-process://") {
            return foundationModelsRunner.stream(command: command)
        }
        return processRunner.stream(command: command)
    }
}

/// Centralised factory used by `RunDispatcher` and the SwiftUI command
/// preview helpers. Picks the right adapter for a provider so we don't
/// scatter `if id == "apple.foundation-models"` checks across the codebase.
enum AgentAdapterFactory {
    static func makeAdapter(
        providerID: String,
        commandProfile: ProviderCommandProfileSnapshot? = nil
    ) -> AgentCLIAdapter {
        if providerID == FoundationModelsAdapter.catalogProviderID {
            return FoundationModelsAdapter()
        }
        return GenericCLIAdapter(providerID: providerID, commandProfile: commandProfile)
    }
}
