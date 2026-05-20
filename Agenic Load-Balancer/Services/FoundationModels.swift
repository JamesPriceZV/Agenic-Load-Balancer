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

// MARK: - Phase 7.2: Structured outcome classification

/// Sendable result produced by analysing a run's stdout/stderr with
/// Foundation Models. All fields are value types so the struct is Sendable.
struct RunClassificationResult: Sendable, Equatable {
    let filesChanged: [String]
    let testsPassed: Int
    let testsFailed: Int
    let oneLineDescription: String
    let suggestedAccuracyRating: AccuracyRating
}

/// Abstraction over on-device outcome classification so the dispatcher
/// can be tested with a scripted stub without Apple Intelligence.
protocol OutcomeClassifying: Sendable {
    func classify(stdout: String, stderr: String, prompt: String) async -> RunClassificationResult?
}

/// Test stub — returns a pre-configured result on every call.
struct StubOutcomeClassifier: OutcomeClassifying {
    let result: RunClassificationResult?
    func classify(stdout: String, stderr: String, prompt: String) async -> RunClassificationResult? { result }
}

/// Production classifier. Gated on Foundation Models availability; falls back
/// to `nil` (no classification) when Apple Intelligence is disabled or the
/// framework is absent, which the caller treats as "no auto-classification".
actor LiveOutcomeClassifier: OutcomeClassifying {
    private let availabilityChecker: any FoundationModelsAvailabilityChecking

    init(availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker()) {
        self.availabilityChecker = availabilityChecker
    }

    func classify(stdout: String, stderr: String, prompt: String) async -> RunClassificationResult? {
        guard availabilityChecker.currentAvailability().isAvailable, !stdout.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await classifyWithFoundationModels(stdout: stdout, stderr: stderr, prompt: prompt)
        }
        return nil
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func classifyWithFoundationModels(stdout: String, stderr: String, prompt: String) async -> RunClassificationResult? {
        do {
            let session = LanguageModelSession(instructions: """
                You classify the outcome of AI coding agent runs. Extract structured metadata \
                from the provided stdout/stderr. Be accurate and concise. Use 0 for test counts \
                when tests were not run. Files should be relative paths or filenames only.
                """)
            let cap = 6000
            let outputText: String = stderr.isEmpty
                ? String(stdout.prefix(cap))
                : "\(String(stdout.prefix(cap / 2)))\n---STDERR---\n\(String(stderr.prefix(cap / 2)))"
            let userMessage = "Prompt: \(prompt.prefix(300))\n\nOutput:\n\(outputText)"
            let response = try await session.respond(to: userMessage, generating: RunSummaryOutput.self)
            return RunClassificationResult(from: response.content)
        } catch {
            return nil
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct RunSummaryOutput {
    @Guide(description: "Relative paths or filenames of files created or modified. Empty if none.")
    let filesChanged: [String]

    @Guide(description: "Number of tests that passed. Use 0 when tests were not run.")
    let testsPassed: Int

    @Guide(description: "Number of tests that failed. Use 0 when tests were not run.")
    let testsFailed: Int

    @Guide(description: "One sentence describing what the run accomplished or attempted.")
    let oneLineDescription: String

    @Guide(description: "Accuracy category that best characterises this run's outcome.")
    let suggestedAccuracy: SuggestedAccuracy

    @Generable
    enum SuggestedAccuracy {
        case correct
        case minorFixNeeded
        case debugNeeded
        case recodeNeeded
        case brokeBuildOrTests
    }
}

@available(macOS 26.0, *)
private extension RunClassificationResult {
    init(from output: RunSummaryOutput) {
        let rating: AccuracyRating
        switch output.suggestedAccuracy {
        case .correct: rating = .correct
        case .minorFixNeeded: rating = .minorFixNeeded
        case .debugNeeded: rating = .debugNeeded
        case .recodeNeeded: rating = .recodeNeeded
        case .brokeBuildOrTests: rating = .brokeBuildOrTests
        }
        self.init(
            filesChanged: output.filesChanged,
            testsPassed: output.testsPassed,
            testsFailed: output.testsFailed,
            oneLineDescription: output.oneLineDescription,
            suggestedAccuracyRating: rating
        )
    }
}
#endif

// MARK: - Phase 7.3: Tool-calling command bar

/// Observable coordinator for the natural-language command bar. Lives on the
/// main actor; the actual Foundation Models session is created inside a task
/// behind availability guards so the coordinator compiles on all platforms.
@MainActor
@Observable
final class CommandBarCoordinator {
    private(set) var response: String = ""
    private(set) var isGenerating: Bool = false
    private(set) var errorMessage: String?
    var question: String = ""

    @ObservationIgnored private var streamTask: Task<Void, Never>?

    func ask(providers: [AgentProviderSnapshot], usage: [UsageSnapshot], accuracy: [AccuracySnapshot]) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        streamTask?.cancel()
        response = ""
        errorMessage = nil
        isGenerating = true

        let p = providers
        let u = usage
        let a = accuracy

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let availability = SystemLanguageModelAvailabilityChecker().currentAvailability()
            guard availability.isAvailable else {
                self.errorMessage = availability.message
                self.isGenerating = false
                return
            }
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                do {
                    let rankTool = RankAgentsTool(providers: p, usageSnapshots: u, accuracySnapshots: a)
                    let metricsTool = ReadDashboardMetricsTool(usageSnapshots: u, accuracySnapshots: a)
                    let session = LanguageModelSession(
                        tools: [rankTool, metricsTool],
                        instructions: """
                            You are an intelligent assistant for the Agenic Load-Balancer, a macOS \
                            orchestration console that routes coding prompts to AI providers. Help \
                            the user understand routing decisions, provider metrics, and coordination \
                            state. Use the available tools to access live data. Keep answers concise.
                            """
                    )
                    for try await partial in session.streamResponse(to: q) {
                        if Task.isCancelled { break }
                        self.response = partial.content
                    }
                } catch {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            } else {
                self.errorMessage = "Foundation Models requires macOS 26 or later."
            }
            #else
            self.errorMessage = "Foundation Models framework is not available in this build."
            #endif
            self.isGenerating = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        isGenerating = false
    }

    func reset() {
        cancel()
        question = ""
        response = ""
        errorMessage = nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private struct RankAgentsTool: Tool {
    let name = "rank_agents"
    let description = "Rank AI coding providers for a given task. Returns the top 3 with scores and rationale."

    @Generable
    struct Arguments {
        @Guide(description: "The coding task or user prompt to rank providers for.")
        let prompt: String
    }

    let providers: [AgentProviderSnapshot]
    let usageSnapshots: [UsageSnapshot]
    let accuracySnapshots: [AccuracySnapshot]

    func call(arguments: Arguments) async throws -> ToolOutput {
        let ranked = await AppServices.routingEngine.rank(
            prompt: arguments.prompt,
            mode: .implementation,
            providers: providers,
            usage: usageSnapshots,
            accuracy: accuracySnapshots,
            coordinationEvents: []
        )
        guard !ranked.isEmpty else {
            return ToolOutput(string: "No providers are currently available or enabled.")
        }
        let lines = ranked.prefix(3).map { score in
            "• \(score.providerName): \(score.totalScore.formatted(.percent.precision(.fractionLength(0)))) — \(score.rationale)"
        }
        return ToolOutput(string: lines.joined(separator: "\n"))
    }
}

@available(macOS 26.0, *)
private struct ReadDashboardMetricsTool: Tool {
    let name = "read_dashboard_metrics"
    let description = "Read current provider metrics: usage, success rates, latency, and estimated costs."

    @Generable
    struct Arguments {
        @Guide(description: "Provider ID to filter by, or empty string for all providers.")
        let providerID: String
    }

    let usageSnapshots: [UsageSnapshot]
    let accuracySnapshots: [AccuracySnapshot]

    func call(arguments: Arguments) async throws -> ToolOutput {
        let filter = arguments.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshots = filter.isEmpty
            ? usageSnapshots
            : usageSnapshots.filter { $0.providerID.contains(filter) }
        guard !snapshots.isEmpty else {
            return ToolOutput(string: "No usage data available.")
        }
        let lines = snapshots.map { snap in
            let acc = accuracySnapshots.first { $0.providerID == snap.providerID }
            return "• \(snap.providerID): calls=\(snap.callsToday), " +
                "success=\(snap.successRate.formatted(.percent.precision(.fractionLength(0)))), " +
                "cost=\(snap.estimatedCostToday.formatted(.currency(code: "USD"))), " +
                "accuracy=\((acc?.averageScore ?? 0.62).formatted(.percent.precision(.fractionLength(0))))"
        }
        return ToolOutput(string: lines.joined(separator: "\n"))
    }
}
#endif

// MARK: - Phase 7.4: Intelligent AgentNotes preflight + merge proposal

/// Summarises AgentNotes.md content relevant to a specific prompt, replacing
/// the byte-truncated raw excerpt with a focused, on-device-generated summary.
protocol AgentNotesSummarizing: Sendable {
    func summarize(content: String, forPrompt prompt: String) async -> String?
}

/// Test stub — returns the pre-configured string on every call.
struct StubAgentNotesSummarizer: AgentNotesSummarizing {
    let result: String?
    func summarize(content: String, forPrompt prompt: String) async -> String? { result }
}

/// Production summariser. Returns `nil` when Foundation Models is unavailable
/// so callers fall back to the raw truncated excerpt.
actor LiveAgentNotesSummarizer: AgentNotesSummarizing {
    private let availabilityChecker: any FoundationModelsAvailabilityChecking

    init(availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker()) {
        self.availabilityChecker = availabilityChecker
    }

    func summarize(content: String, forPrompt prompt: String) async -> String? {
        guard availabilityChecker.currentAvailability().isAvailable, !content.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await summarizeWithFoundationModels(content: content, prompt: prompt)
        }
        return nil
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func summarizeWithFoundationModels(content: String, prompt: String) async -> String? {
        do {
            let session = LanguageModelSession(instructions: """
                You extract relevant coordination claims from AgentNotes.md files. Given a \
                task prompt, identify only the active work items, blockers, and claims that \
                directly affect that task. Format as 3–5 concise bullet points. Skip completed \
                work, historical checkpoints, and unrelated sections.
                """)
            let message = "Task: \(prompt.prefix(400))\n\nAgentNotes.md:\n\(content.prefix(6000))"
            var accumulated = ""
            for try await partial in session.streamResponse(to: message) {
                accumulated = partial.content
            }
            return accumulated.isEmpty ? nil : accumulated
        } catch {
            return nil
        }
    }
    #endif
}

/// Proposes a merged AgentNotes.md when the on-disk version has diverged from
/// the SwiftData-generated version. The user still gates the final write
/// through the existing `confirmationDialog`.
protocol AgentNotesMergeProposing: Sendable {
    func proposeMerge(onDisk: String, generated: String) async -> String?
}

/// Test stub.
struct StubAgentNotesMergeProposer: AgentNotesMergeProposing {
    let result: String?
    func proposeMerge(onDisk: String, generated: String) async -> String? { result }
}

/// Production merge proposer backed by Foundation Models.
actor LiveAgentNotesMergeProposer: AgentNotesMergeProposing {
    private let availabilityChecker: any FoundationModelsAvailabilityChecking

    init(availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker()) {
        self.availabilityChecker = availabilityChecker
    }

    func proposeMerge(onDisk: String, generated: String) async -> String? {
        guard availabilityChecker.currentAvailability().isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await proposeWithFoundationModels(onDisk: onDisk, generated: generated)
        }
        return nil
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func proposeWithFoundationModels(onDisk: String, generated: String) async -> String? {
        do {
            let session = LanguageModelSession(instructions: """
                You merge two versions of an AgentNotes.md coordination file. Preserve all \
                active work claims, checkpoints, and blockers from both versions. Remove \
                duplicates. Maintain the markdown structure from the generated version. \
                Output only the merged file content — no commentary.
                """)
            let message = """
                Merge these two AgentNotes.md versions:

                === ON-DISK VERSION ===
                \(onDisk.prefix(4000))

                === GENERATED VERSION (from SwiftData) ===
                \(generated.prefix(4000))
                """
            var accumulated = ""
            for try await partial in session.streamResponse(to: message) {
                accumulated = partial.content
            }
            return accumulated.isEmpty ? nil : accumulated
        } catch {
            return nil
        }
    }
    #endif
}

// MARK: - Phase 7.5: Routing tie-breaker

/// On-device explanation produced when the top providers score within 5% of
/// each other. Optional layer — deterministic scoring stays canonical.
struct RoutingTieBreakResult: Sendable, Equatable {
    let preferredProviderID: String
    let reasoning: String
}

/// Abstraction so the tie-breaker is testable without Apple Intelligence.
protocol RoutingTieBreaking: Sendable {
    func tieBreak(prompt: String, candidates: [RoutingScoreBreakdown]) async -> RoutingTieBreakResult?
}

/// Test stub.
struct StubRoutingTieBreaker: RoutingTieBreaking {
    let result: RoutingTieBreakResult?
    func tieBreak(prompt: String, candidates: [RoutingScoreBreakdown]) async -> RoutingTieBreakResult? { result }
}

/// Production tie-breaker. Uses `@Generable` guided generation to produce a
/// typed `RoutingTieBreakResult`; falls back to `nil` when unavailable.
actor LiveRoutingTieBreaker: RoutingTieBreaking {
    private let availabilityChecker: any FoundationModelsAvailabilityChecking

    init(availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker()) {
        self.availabilityChecker = availabilityChecker
    }

    func tieBreak(prompt: String, candidates: [RoutingScoreBreakdown]) async -> RoutingTieBreakResult? {
        guard availabilityChecker.currentAvailability().isAvailable, candidates.count >= 2 else { return nil }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await tieBreakWithFoundationModels(prompt: prompt, candidates: candidates)
        }
        return nil
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func tieBreakWithFoundationModels(prompt: String, candidates: [RoutingScoreBreakdown]) async -> RoutingTieBreakResult? {
        do {
            let session = LanguageModelSession(instructions: """
                You are a routing expert for AI coding agents. Given a close tie in routing \
                scores, pick the best provider for the specific task. Return the providerID \
                exactly as given in the candidate list.
                """)
            let validIDs = candidates.map(\.providerID).joined(separator: ", ")
            let candidateList = candidates.map { c in
                "ID: \(c.providerID), Name: \(c.providerName), Score: \(String(format: "%.2f", c.totalScore)), Info: \(c.rationale)"
            }.joined(separator: "\n")
            let userMessage = """
                Task: \(prompt.prefix(400))

                Candidates (valid providerIDs: \(validIDs)):
                \(candidateList)

                Which provider is best for this task and why?
                """
            let response = try await session.respond(to: userMessage, generating: RoutingTieBreakOutput.self)
            return RoutingTieBreakResult(
                preferredProviderID: response.content.preferredProviderID,
                reasoning: response.content.reasoning
            )
        } catch {
            return nil
        }
    }

    @available(macOS 26.0, *)
    @Generable
    private struct RoutingTieBreakOutput {
        @Guide(description: "The providerID of the recommended provider, copied exactly from the candidate list.")
        let preferredProviderID: String

        @Guide(description: "One to two sentences explaining why this provider best fits the given task.")
        let reasoning: String
    }
    #endif
}
