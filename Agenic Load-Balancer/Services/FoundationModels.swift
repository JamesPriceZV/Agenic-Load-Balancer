//
//  FoundationModels.swift
//  Agenic Load-Balancer
//
//  Created by Claude on 5/5/26.
//
//  Phase 7.1: plumbing for Apple Foundation Models as a first-class
//  provider inside the existing run pipeline.
//
//  - `FoundationModelsAvailability` is a small Sendable sum type that the
//    rest of the app reasons about, kept independent of the FoundationModels
//    framework so the project still type-checks on SDKs that don't ship it.
//  - `FoundationModelsAvailabilityChecking` and
//    `FoundationModelsSessionDriving` are the two abstraction protocols.
//    Tests inject scripted stubs; production wires the real
//    `SystemLanguageModel.default.availability` and
//    `LanguageModelSession.streamResponse(to:)` calls behind a
//    `#if canImport(FoundationModels)` gate.
//  - `FoundationModelsAdapter` produces an in-process `AgentCommand`
//    tagged with a sentinel `executablePath`.
//  - `FoundationModelsRunner` consumes that command, calls the session
//    driver for accumulated text snapshots, computes per-snapshot deltas,
//    and emits them as line-buffered `AgentProcessEvent.standardOutput`
//    lines so the existing live console / outcome ledger / dashboard work
//    without modification.
//  - `CompositeAgentRunner` dispatches by `executablePath` prefix so the
//    same `RunDispatcher` handles both child processes and on-device
//    sessions.
//
//  Cross-cutting design rule: every Foundation Models call site checks
//  availability via the protocol below, then degrades gracefully when
//  Apple Intelligence is unavailable (stderr line + non-zero exit code,
//  surfaced through the existing approval-sheet failure path).
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Availability

/// Sendable sum type that hides the FoundationModels import behind a small,
/// testable boundary.
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

/// Indirection so the adapter / runner / monitor don't talk to
/// `SystemLanguageModel.default` directly.
protocol FoundationModelsAvailabilityChecking: Sendable {
    func currentAvailability() -> FoundationModelsAvailability
}

/// Production checker. When the FoundationModels framework is available at
/// build time AND we're running on macOS 26.0+, this resolves the real
/// `SystemLanguageModel.default.availability`. Otherwise it reports
/// `.frameworkUnavailable` so the runner emits a clear error rather than
/// crashing on a missing dyld symbol.
struct SystemLanguageModelAvailabilityChecker: FoundationModelsAvailabilityChecking {
    init() {}

    func currentAvailability() -> FoundationModelsAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return Self.translate(SystemLanguageModel.default.availability)
        }
        return .frameworkUnavailable
        #else
        return .frameworkUnavailable
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func translate(_ availability: SystemLanguageModel.Availability) -> FoundationModelsAvailability {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            case .deviceNotEligible:
                return .deviceNotEligible
            @unknown default:
                return .unknown(String(describing: reason))
            }
        @unknown default:
            return .unknown(String(describing: availability))
        }
    }
    #endif
}

/// Test-friendly stub. Returns the configured value on every call.
struct StubFoundationModelsAvailabilityChecker: FoundationModelsAvailabilityChecking {
    let value: FoundationModelsAvailability

    init(_ value: FoundationModelsAvailability) {
        self.value = value
    }

    func currentAvailability() -> FoundationModelsAvailability { value }
}

// MARK: - Session driver

/// Streams accumulated text snapshots from a Foundation Models session.
/// Each yielded `String` is the full response so far (NOT a delta) — the
/// runner is responsible for diffing snapshot-to-snapshot and emitting
/// per-line stdout.
protocol FoundationModelsSessionDriving: Sendable {
    func streamSnapshots(prompt: String) -> AsyncThrowingStream<String, Error>
}

#if canImport(FoundationModels)
/// Production session driver backed by the real
/// `LanguageModelSession.streamResponse(to:)`. The session is constructed
/// inside the spawned task and never escapes it, so its non-Sendable
/// nature stays inside one isolation domain.
@available(macOS 26.0, *)
struct LiveFoundationModelsSessionDriver: FoundationModelsSessionDriving {
    init() {}

    func streamSnapshots(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession()
                    for try await partial in session.streamResponse(to: prompt) {
                        if Task.isCancelled { break }
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
#endif

// MARK: - Adapter

/// `AgentCLIAdapter` for the in-process Apple Foundation Models provider.
/// Tags the command with a sentinel `executablePath`
/// (`in-process://foundation-models`) that the `CompositeAgentRunner`
/// routes to `FoundationModelsRunner`.
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
        case .available:
            mappedState = .available
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

// MARK: - Runner

/// In-process runner for Foundation Models commands. Uses the injected
/// `FoundationModelsSessionDriving` to obtain accumulated text snapshots,
/// computes deltas, and emits them as line-buffered
/// `AgentProcessEvent.standardOutput` lines.
struct FoundationModelsRunner: AgentRunning {
    let availabilityChecker: any FoundationModelsAvailabilityChecking
    let sessionDriver: (any FoundationModelsSessionDriving)?

    init(
        availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker(),
        sessionDriver: (any FoundationModelsSessionDriving)? = FoundationModelsRunner.defaultSessionDriver()
    ) {
        self.availabilityChecker = availabilityChecker
        self.sessionDriver = sessionDriver
    }

    /// Returns the live session driver when the FoundationModels framework
    /// is available; `nil` otherwise. Tests pass an explicit driver so this
    /// production default is never observed by them.
    static func defaultSessionDriver() -> (any FoundationModelsSessionDriving)? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return LiveFoundationModelsSessionDriver()
        }
        return nil
        #else
        return nil
        #endif
    }

    func stream(command: AgentCommand) -> AsyncThrowingStream<AgentProcessEvent, Error> {
        let prompt = Self.extractPrompt(from: command.arguments)
        let availability = availabilityChecker.currentAvailability()
        let driver = sessionDriver

        return AsyncThrowingStream { continuation in
            continuation.yield(.started(command: command.displayCommand))

            // Availability gate: Apple Intelligence off, model not ready,
            // device not eligible, or framework not present. Surface the
            // user-facing message via stderr and exit 78 (EX_CONFIG) so the
            // approval sheet's failure path explains why nothing ran.
            guard availability.isAvailable else {
                continuation.yield(.standardError("Apple Foundation Models unavailable: \(availability.message)"))
                continuation.yield(.finished(exitCode: 78))
                continuation.finish()
                return
            }
            guard let driver else {
                continuation.yield(.standardError("Apple Foundation Models framework is not linked into this build."))
                continuation.yield(.finished(exitCode: 78))
                continuation.finish()
                return
            }

            let task = Task {
                var emittedPrefixCount = 0
                var pendingLine = ""
                var emittedAnyLine = false

                func emitDelta(_ delta: String) {
                    let combined = pendingLine + delta
                    let segments = combined.split(
                        separator: "\n",
                        omittingEmptySubsequences: false
                    )
                    guard !segments.isEmpty else {
                        pendingLine = ""
                        return
                    }
                    for index in 0..<(segments.count - 1) {
                        let line = String(segments[index])
                        continuation.yield(.standardOutput(line))
                        emittedAnyLine = true
                    }
                    pendingLine = String(segments[segments.count - 1])
                }

                do {
                    for try await snapshot in driver.streamSnapshots(prompt: prompt) {
                        if Task.isCancelled {
                            continuation.yield(.standardError("Foundation Models session cancelled."))
                            continuation.yield(.finished(exitCode: 130))
                            continuation.finish()
                            return
                        }
                        guard snapshot.count > emittedPrefixCount else { continue }
                        let deltaStartIndex = snapshot.index(
                            snapshot.startIndex,
                            offsetBy: emittedPrefixCount
                        )
                        let delta = String(snapshot[deltaStartIndex...])
                        emittedPrefixCount = snapshot.count
                        emitDelta(delta)
                    }

                    if !pendingLine.isEmpty {
                        continuation.yield(.standardOutput(pendingLine))
                        emittedAnyLine = true
                    }
                    if !emittedAnyLine {
                        // Surface a heartbeat so the dashboard ledger and
                        // usage estimator see at least one stdout line.
                        continuation.yield(.standardOutput("[Foundation Models] no content emitted."))
                    }
                    continuation.yield(.finished(exitCode: 0))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.standardError("Foundation Models session cancelled."))
                    continuation.yield(.finished(exitCode: 130))
                    continuation.finish()
                } catch {
                    let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    continuation.yield(.standardError("Foundation Models error: \(description)"))
                    continuation.yield(.finished(exitCode: 1))
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// The in-process command's last argument is the coordination-wrapped
    /// prompt; everything before it is metadata that the runner ignores.
    private static func extractPrompt(from arguments: [String]) -> String {
        arguments.last ?? ""
    }
}

// MARK: - Composite runner

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

// MARK: - Adapter factory

/// Centralised factory used by `RunDispatcher`, the SwiftUI command preview
/// helpers, and `ProviderHealthMonitor`. Picks the right adapter for a
/// provider so we don't scatter `if id == "apple.foundation-models"`
/// checks across the codebase.
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
