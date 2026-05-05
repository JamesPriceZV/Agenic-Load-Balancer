//
//  RunDispatcher.swift
//  Agenic Load-Balancer
//
//  Created by OpenAI Codex on 5/5/26.
//
//  Phase 2: live run pipeline. Owns the lifecycle of an approved routing
//  decision — persists the approval records, streams the underlying
//  `AgentProcessRunner`, exposes observable state to SwiftUI, and writes the
//  final RunOutcome, UsageLedger, and Coordination updates when the run
//  finishes (or fails, or is cancelled by the user).
//

import Foundation
import Observation
import SwiftData

/// Bundle of inputs needed to dispatch an approved routing decision.
struct RunPlan: Sendable {
    let providerSnapshot: AgentProviderSnapshot
    let providerID: String
    let providerName: String
    let prompt: String
    let projectID: String?
    let projectName: String?
    let projectRootPath: String?
    let mode: AgentExecutionMode
    let score: RoutingScoreBreakdown
    let promptExcerptSyncEnabled: Bool
}

/// MainActor-isolated, observable controller for the active run.
///
/// Created by the prompt router view, kept alive while the approval sheet is
/// open, and inspected by SwiftUI to render the live console.
@MainActor
@Observable
final class RunDispatcher {
    enum LiveStatus: String, Sendable, Equatable {
        case idle
        case preparing
        case running
        case succeeded
        case failed
        case cancelled

        var label: String {
            switch self {
            case .idle: "Idle"
            case .preparing: "Preparing"
            case .running: "Running"
            case .succeeded: "Succeeded"
            case .failed: "Failed"
            case .cancelled: "Cancelled"
            }
        }

        var isTerminal: Bool {
            self == .succeeded || self == .failed || self == .cancelled
        }
    }

    struct LogLine: Identifiable, Sendable, Hashable {
        enum Kind: String, Sendable {
            case stdout
            case stderr
            case system
        }

        let id: UUID
        let kind: Kind
        let text: String
        let timestamp: Date

        init(id: UUID = UUID(), kind: Kind, text: String, timestamp: Date = Date()) {
            self.id = id
            self.kind = kind
            self.text = text
            self.timestamp = timestamp
        }
    }

    enum CheckpointStatus: Sendable, Equatable {
        case notRequested
        case pending
        case succeeded(sha: String, pushed: Bool, pushError: String?)
        case nothingToCommit
        case failed(reason: String)

        var label: String {
            switch self {
            case .notRequested: "—"
            case .pending: "Committing…"
            case .succeeded(let sha, let pushed, _):
                pushed ? "Committed & pushed \(sha.prefix(8))" : "Committed \(sha.prefix(8))"
            case .nothingToCommit: "Nothing to commit"
            case .failed(let reason): "Checkpoint failed: \(reason)"
            }
        }
    }

    // MARK: Observable state surfaced to SwiftUI
    private(set) var status: LiveStatus = .idle
    private(set) var logs: [LogLine] = []
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?
    private(set) var exitCode: Int32?
    private(set) var displayedCommand: String = ""
    private(set) var lastError: String?
    private(set) var activeRunID: String?
    private(set) var activeOutcomeID: String?
    private(set) var promptTokens: Int = 0
    private(set) var completionTokens: Int = 0
    private(set) var checkpointStatus: CheckpointStatus = .notRequested
    private(set) var preflightExcerpt: String?

    // MARK: Internal collaborators (excluded from observation tracking)
    @ObservationIgnored private let runner: AgentRunning
    @ObservationIgnored private let adapterFactory: @Sendable (String, ProviderCommandProfileSnapshot?) -> AgentCLIAdapter
    @ObservationIgnored private let coordinationActor: ProjectCoordinationActor
    @ObservationIgnored private let cloudSync: CloudSyncCoordinator
    @ObservationIgnored private let gitCheckpoint: GitCheckpointing
    @ObservationIgnored private let now: @Sendable () -> Date

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var activeOutcome: RunOutcomeRecord?
    @ObservationIgnored private var activeUsage: UsageLedgerEntry?
    @ObservationIgnored private var activeCoordination: CoordinationEventRecord?
    @ObservationIgnored private var activePlan: RunPlan?
    @ObservationIgnored private var userCancelRequested: Bool = false

    init(
        runner: AgentRunning = AgentProcessRunner(),
        adapterFactory: @escaping @Sendable (String, ProviderCommandProfileSnapshot?) -> AgentCLIAdapter = { id, profile in
            AgentAdapterFactory.makeAdapter(providerID: id, commandProfile: profile)
        },
        coordinationActor: ProjectCoordinationActor = AppServices.coordination,
        cloudSync: CloudSyncCoordinator = AppServices.cloudSync,
        gitCheckpoint: GitCheckpointing = AppServices.gitCheckpoint,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runner = runner
        self.adapterFactory = adapterFactory
        self.coordinationActor = coordinationActor
        self.cloudSync = cloudSync
        self.gitCheckpoint = gitCheckpoint
        self.now = now
    }

    // MARK: Public API

    /// Reset all observable state so the sheet can be reused for a new run.
    func reset() {
        streamTask?.cancel()
        streamTask = nil
        status = .idle
        logs = []
        startedAt = nil
        endedAt = nil
        exitCode = nil
        displayedCommand = ""
        lastError = nil
        activeRunID = nil
        activeOutcomeID = nil
        promptTokens = 0
        completionTokens = 0
        checkpointStatus = .notRequested
        preflightExcerpt = nil
        activeOutcome = nil
        activeUsage = nil
        activeCoordination = nil
        activePlan = nil
        userCancelRequested = false
    }

    /// Persist approval records and start streaming the underlying CLI.
    /// Errors at this stage (missing executable, mode mismatch) are persisted
    /// as a failed run rather than being thrown, so the sheet can render the
    /// failure inline alongside the originally-approved command preview.
    ///
    /// `agentNotesExcerpt` is the current on-disk content (or `nil` when
    /// the project has no AgentNotes file yet). When supplied it gets
    /// embedded in the prompt so the agent sees the active claims directly,
    /// not just an instruction to re-read the file.
    func dispatch(
        plan: RunPlan,
        agentNotesExcerpt: String? = nil,
        modelContext: ModelContext
    ) {
        reset()
        status = .preparing
        activePlan = plan
        preflightExcerpt = agentNotesExcerpt
        appendSystem("Approved \(plan.providerName) for \(plan.mode.label).")
        if agentNotesExcerpt?.isEmpty == false {
            appendSystem("AgentNotes preflight injected (\(agentNotesExcerpt?.count ?? 0) chars).")
        }

        let profile = Self.fetchEnabledCommandProfile(
            providerID: plan.providerID,
            in: modelContext
        )
        let adapter = adapterFactory(plan.providerID, profile)

        let promptForCommand = Self.composeCommandPrompt(
            userPrompt: plan.prompt,
            agentNotesExcerpt: agentNotesExcerpt
        )

        let command: AgentCommand
        do {
            command = try adapter.buildCommand(
                prompt: promptForCommand,
                projectPath: plan.projectRootPath,
                mode: plan.mode,
                provider: plan.providerSnapshot
            )
        } catch let error as AgentProcessError {
            persistFailedDispatch(plan: plan, modelContext: modelContext, message: error.errorDescription ?? "Failed to build command")
            return
        } catch {
            persistFailedDispatch(plan: plan, modelContext: modelContext, message: error.localizedDescription)
            return
        }

        displayedCommand = command.displayCommand
        let startedAtTimestamp = now()
        startedAt = startedAtTimestamp

        let records = persistApprovalRecords(plan: plan, command: command, modelContext: modelContext, startedAt: startedAtTimestamp)
        activeOutcome = records.outcome
        activeUsage = records.usage
        activeCoordination = records.coordination
        activeRunID = records.outcome.runID
        activeOutcomeID = records.outcome.identifier

        status = .running
        appendSystem("Launching: \(command.displayCommand)")

        let stream = runner.stream(command: command)

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await event in stream {
                    if Task.isCancelled { break }
                    self.handle(event: event, plan: plan, modelContext: modelContext)
                    if self.status.isTerminal { break }
                }
                if !self.status.isTerminal {
                    if self.userCancelRequested || Task.isCancelled {
                        self.finalize(plan: plan, modelContext: modelContext, terminal: .cancelled, code: nil, errorMessage: "Run cancelled before completion.")
                    } else {
                        self.finalize(plan: plan, modelContext: modelContext, terminal: .succeeded, code: self.exitCode, errorMessage: nil)
                    }
                }
            } catch is CancellationError {
                self.finalize(plan: plan, modelContext: modelContext, terminal: .cancelled, code: nil, errorMessage: "Run cancelled.")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let terminal: LiveStatus = self.userCancelRequested ? .cancelled : .failed
                self.finalize(plan: plan, modelContext: modelContext, terminal: terminal, code: nil, errorMessage: terminal == .cancelled ? nil : message)
            }

            // Post-run: git checkpoint when the user explicitly approved a
            // commit/push mode and the run actually succeeded.
            if self.status == .succeeded && plan.mode == .commitPushCheckpoint {
                await self.performGitCheckpoint(plan: plan, modelContext: modelContext)
            }
        }
    }

    /// Build the prompt the agent will actually receive. Embeds the
    /// AgentNotes excerpt above the user's prompt so cross-agent claims are
    /// visible as part of the run's input.
    static func composeCommandPrompt(userPrompt: String, agentNotesExcerpt: String?) -> String {
        guard let excerpt = agentNotesExcerpt, !excerpt.isEmpty else {
            return userPrompt
        }
        return """
        Active AgentNotes excerpt (read-only, latest snapshot from disk):
        \(excerpt)
        ---
        \(userPrompt)
        """
    }

    /// Request cancellation of the in-flight run. Idempotent.
    func cancel() {
        guard status == .running || status == .preparing else { return }
        userCancelRequested = true
        appendSystem("Cancellation requested.")
        streamTask?.cancel()
    }

    /// SwiftUI hook for users to rate the outcome from the live console.
    func rateOutcome(_ rating: AccuracyRating, in modelContext: ModelContext) {
        guard let outcome = activeOutcome else { return }
        outcome.accuracyRating = rating.rawValue
        outcome.endedAt = endedAt ?? now()
        try? modelContext.save()
    }

    /// Test-friendly helper that yields until the run reaches a terminal state.
    /// Safe to call on `@MainActor` tests because the streaming Task is also
    /// MainActor-isolated and will share execution slices via `Task.sleep`.
    func awaitTermination(timeout: TimeInterval = 5.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !status.isTerminal && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Phase 6: shell out to git after a successful run in
    /// `.commitPushCheckpoint` mode. Stamps the commit hash on the active
    /// `RunOutcomeRecord` and `CoordinationEventRecord`, appends to
    /// AgentNotes through the coordination actor, and updates
    /// `checkpointStatus` for the UI.
    private func performGitCheckpoint(plan: RunPlan, modelContext: ModelContext) async {
        guard let rootPath = plan.projectRootPath, !rootPath.isEmpty else {
            checkpointStatus = .failed(reason: "No project root path; nothing to checkpoint.")
            appendSystem("Skipped checkpoint: project has no local root path.")
            return
        }

        checkpointStatus = .pending
        appendSystem("Starting git checkpoint…")

        let projectURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let messageBody = plan.prompt.split(separator: "\n").first.map(String.init) ?? plan.prompt
        let trimmed = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = trimmed.count > 72 ? String(trimmed.prefix(72)) + "…" : trimmed
        let commitMessage = """
        Agenic Load-Balancer · \(plan.providerName) · \(plan.mode.label)

        \(summary.isEmpty ? "Approved checkpoint" : summary)

        Run-ID: \(activeRunID ?? "n/a")
        """

        do {
            let result = try await gitCheckpoint.commit(
                in: projectURL,
                message: commitMessage,
                push: true
            )

            if let outcome = activeOutcome {
                outcome.commitSHA = result.sha
                outcome.buildResult = result.pushed ? "checkpointedAndPushed" : "checkpointedLocal"
            }
            if let event = activeCoordination {
                event.commitSHA = result.sha
                let pushedNote = result.pushed ? " (pushed)" : (result.pushError.map { " (push failed: \($0))" } ?? " (local only)")
                event.detail += "\nCheckpoint commit: \(result.sha)\(pushedNote)"
                event.status = CoordinationStatus.checkpointed.rawValue
            }
            try? modelContext.save()

            checkpointStatus = .succeeded(
                sha: result.sha,
                pushed: result.pushed,
                pushError: result.pushError
            )
            appendSystem("Git checkpoint \(result.sha) — push: \(result.pushed ? "ok" : (result.pushError ?? "skipped")).")

            if let projectName = plan.projectName, let coordination = activeCoordination {
                let snapshot = coordination.snapshot()
                let coordinationRef = coordinationActor
                _ = try? await coordinationRef.append(
                    event: snapshot,
                    projectName: projectName,
                    rootPath: rootPath
                )
            }
        } catch let error as GitCheckpointError {
            switch error {
            case .nothingToCommit:
                checkpointStatus = .nothingToCommit
                appendSystem("Git checkpoint: nothing to commit — working tree was clean.")
            default:
                let message = error.errorDescription ?? "\(error)"
                checkpointStatus = .failed(reason: message)
                appendSystem("Git checkpoint failed: \(message)")
            }
        } catch {
            let message = error.localizedDescription
            checkpointStatus = .failed(reason: message)
            appendSystem("Git checkpoint failed: \(message)")
        }
    }

    /// Look up the enabled command profile (if any) for `providerID`.
    /// Returns `nil` when no profile exists or the profile is disabled, so
    /// the adapter falls back to the catalog defaults.
    @MainActor
    private static func fetchEnabledCommandProfile(
        providerID: String,
        in context: ModelContext
    ) -> ProviderCommandProfileSnapshot? {
        let descriptor = FetchDescriptor<ProviderCommandProfile>()
        guard let profiles = try? context.fetch(descriptor) else { return nil }
        return profiles
            .first { $0.providerID == providerID && $0.isEnabled }?
            .snapshot()
    }

    // MARK: Event handling

    private func handle(event: AgentProcessEvent, plan: RunPlan, modelContext: ModelContext) {
        switch event {
        case .started(let command):
            displayedCommand = command
            appendSystem("Process started.")
        case .standardOutput(let line):
            appendLine(.init(kind: .stdout, text: line))
            ingestTokenSignals(in: line)
        case .standardError(let line):
            appendLine(.init(kind: .stderr, text: line))
            ingestTokenSignals(in: line)
        case .finished(let code):
            exitCode = code
            let terminal: LiveStatus = userCancelRequested ? .cancelled : (code == 0 ? .succeeded : .failed)
            let message: String? = (terminal == .failed) ? "Process exited with code \(code)." : nil
            finalize(plan: plan, modelContext: modelContext, terminal: terminal, code: code, errorMessage: message)
        }
    }

    private func appendLine(_ line: LogLine) {
        logs.append(line)
        // Cap visible log buffer so very chatty tools don't blow up memory.
        if logs.count > 2_000 {
            logs.removeFirst(logs.count - 2_000)
        }
    }

    private func appendSystem(_ message: String) {
        appendLine(.init(kind: .system, text: message))
    }

    // MARK: Persistence

    private struct ApprovalRecords {
        let thread: PromptThreadRecord
        let message: PromptMessageRecord
        let decision: RoutingDecisionRecord
        let outcome: RunOutcomeRecord
        let usage: UsageLedgerEntry
        let coordination: CoordinationEventRecord
    }

    private func persistApprovalRecords(
        plan: RunPlan,
        command: AgentCommand,
        modelContext: ModelContext,
        startedAt: Date
    ) -> ApprovalRecords {
        let thread = PromptThreadRecord(
            projectID: plan.projectID,
            title: plan.prompt.routerTitle,
            createdAt: startedAt,
            updatedAt: startedAt
        )
        let message = PromptMessageRecord(
            threadID: thread.identifier,
            role: "user",
            providerID: plan.providerID,
            contentExcerpt: plan.promptExcerptSyncEnabled ? plan.prompt : plan.prompt.routerExcerpt,
            createdAt: startedAt
        )
        let decision = RoutingDecisionRecord(
            promptThreadID: thread.identifier,
            selectedProviderID: plan.providerID,
            selectedMode: plan.mode.rawValue,
            scoreSummary: plan.score.rationale,
            estimatedCostUSD: plan.score.estimatedCostUSD,
            limitImpact: plan.score.limitImpact,
            coordinationWarnings: plan.score.coordinationWarning,
            approvedByUser: true,
            createdAt: startedAt
        )
        let outcome = RunOutcomeRecord(
            providerID: plan.providerID,
            projectID: plan.projectID,
            status: RunStatus.running.rawValue,
            startedAt: startedAt
        )
        let usage = UsageLedgerEntry(
            providerID: plan.providerID,
            runID: outcome.runID,
            promptTokens: 0,
            completionTokens: 0,
            callCount: 1,
            estimatedCostUSD: plan.score.estimatedCostUSD,
            durationSeconds: 0,
            sessionSeconds: 0,
            createdAt: startedAt
        )
        let event = CoordinationEventRecord(
            projectID: plan.projectID,
            phase: "Phase 2",
            wave: "Dispatch",
            step: plan.mode.label,
            assignee: plan.providerName,
            status: CoordinationStatus.inProgress.rawValue,
            title: "Running \(plan.providerName) for \(plan.mode.label)",
            detail: "Command: \(command.displayCommand)",
            relatedRunID: outcome.runID,
            createdAt: startedAt
        )

        modelContext.insert(thread)
        modelContext.insert(message)
        modelContext.insert(decision)
        modelContext.insert(outcome)
        modelContext.insert(usage)
        modelContext.insert(event)

        do {
            try modelContext.save()
        } catch {
            appendSystem("Approval save failed: \(error.localizedDescription)")
        }

        let cloudSyncRef = cloudSync
        Task { await cloudSyncRef.recordLocalSave() }

        return ApprovalRecords(
            thread: thread,
            message: message,
            decision: decision,
            outcome: outcome,
            usage: usage,
            coordination: event
        )
    }

    private func persistFailedDispatch(plan: RunPlan, modelContext: ModelContext, message: String) {
        appendSystem(message)
        let timestamp = now()
        let outcome = RunOutcomeRecord(
            providerID: plan.providerID,
            projectID: plan.projectID,
            status: RunStatus.failed.rawValue,
            startedAt: timestamp,
            endedAt: timestamp,
            durationSeconds: 0
        )
        outcome.userFeedback = message

        let coordination = CoordinationEventRecord(
            projectID: plan.projectID,
            phase: "Phase 2",
            wave: "Dispatch",
            step: plan.mode.label,
            assignee: plan.providerName,
            status: CoordinationStatus.blocked.rawValue,
            title: "Dispatch blocked for \(plan.providerName)",
            detail: message,
            relatedRunID: outcome.runID,
            createdAt: timestamp
        )

        modelContext.insert(outcome)
        modelContext.insert(coordination)
        try? modelContext.save()

        activeOutcome = outcome
        activeCoordination = coordination
        activeRunID = outcome.runID
        activeOutcomeID = outcome.identifier
        endedAt = timestamp
        startedAt = timestamp
        lastError = message
        status = .failed

        announceCoordination(plan: plan, event: coordination)
    }

    private func finalize(
        plan: RunPlan,
        modelContext: ModelContext,
        terminal: LiveStatus,
        code: Int32?,
        errorMessage: String?
    ) {
        guard !status.isTerminal else { return }

        let endTimestamp = now()
        endedAt = endTimestamp
        if let code { exitCode = code }
        if let errorMessage { lastError = errorMessage }
        status = terminal

        let durationSeconds = endTimestamp.timeIntervalSince(startedAt ?? endTimestamp)

        if let outcome = activeOutcome {
            outcome.endedAt = endTimestamp
            outcome.durationSeconds = durationSeconds
            outcome.status = {
                switch terminal {
                case .succeeded: return RunStatus.succeeded.rawValue
                case .failed: return RunStatus.failed.rawValue
                case .cancelled: return RunStatus.cancelled.rawValue
                default: return RunStatus.failed.rawValue
                }
            }()
            outcome.buildResult = code.map { code in
                code == 0 ? "exit0" : "exit\(code)"
            } ?? (terminal == .cancelled ? "cancelled" : "noExit")
            if let errorMessage {
                outcome.userFeedback = errorMessage
            }
        }

        if let usage = activeUsage {
            let estimatedTokens: (prompt: Int, completion: Int) = {
                if promptTokens > 0 || completionTokens > 0 {
                    return (promptTokens, completionTokens)
                }
                let stdoutChars = logs
                    .filter { $0.kind == .stdout }
                    .reduce(0) { $0 + $1.text.count }
                let stderrChars = logs
                    .filter { $0.kind == .stderr }
                    .reduce(0) { $0 + $1.text.count }
                let promptApprox = max(plan.prompt.count / 4, 1)
                let completionApprox = max((stdoutChars + stderrChars) / 4, 0)
                return (promptApprox, completionApprox)
            }()
            usage.promptTokens = estimatedTokens.prompt
            usage.completionTokens = estimatedTokens.completion
            usage.durationSeconds = durationSeconds
            usage.sessionSeconds = durationSeconds
        }

        if let coordination = activeCoordination {
            coordination.status = {
                switch terminal {
                case .succeeded: return CoordinationStatus.completed.rawValue
                case .cancelled: return CoordinationStatus.blocked.rawValue
                case .failed: return CoordinationStatus.conflict.rawValue
                default: return CoordinationStatus.blocked.rawValue
                }
            }()
            if let errorMessage {
                coordination.detail += "\n\(errorMessage)"
                coordination.conflictMarker = errorMessage
            } else if terminal == .succeeded, let code {
                coordination.detail += "\nExit code: \(code)"
            }
        }

        do {
            try modelContext.save()
        } catch {
            appendSystem("Final save failed: \(error.localizedDescription)")
        }

        appendSystem("Run \(terminal.label.lowercased()) after \(durationSeconds.formattedDurationSeconds).")

        let cloudSyncRef = cloudSync
        Task { await cloudSyncRef.recordLocalSave() }

        if let coordination = activeCoordination {
            announceCoordination(plan: plan, event: coordination)
        }

        streamTask = nil
    }

    private func announceCoordination(plan: RunPlan, event: CoordinationEventRecord) {
        guard let projectName = plan.projectName, let rootPath = plan.projectRootPath else { return }
        let snapshot = event.snapshot()
        let coordinationRef = coordinationActor
        Task {
            _ = try? await coordinationRef.append(
                event: snapshot,
                projectName: projectName,
                rootPath: rootPath
            )
        }
    }

    private func ingestTokenSignals(in line: String) {
        let parsed = TokenUsageParser.parse(line: line)
        promptTokens += parsed.prompt
        completionTokens += parsed.completion
    }
}

/// Best-effort scanner for inline token usage markers emitted by streaming
/// CLIs (Codex, Claude Code, etc.). When a line contains
/// `"prompt_tokens": <n>` or `"completion_tokens": <n>` (or `prompt_tokens=<n>`
/// shell-style pairs), the values are returned. Otherwise zeros are returned
/// and the dispatcher falls back to a character-based estimate.
enum TokenUsageParser {
    static func parse(line: String) -> (prompt: Int, completion: Int) {
        (
            prompt: extractInt(forKey: "prompt_tokens", in: line),
            completion: extractInt(forKey: "completion_tokens", in: line)
        )
    }

    private static func extractInt(forKey key: String, in line: String) -> Int {
        let patterns = [
            #""\#(key)"\s*:\s*(\d+)"#,
            #"\#(key)\s*[:=]\s*(\d+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range),
               match.numberOfRanges >= 2,
               let captureRange = Range(match.range(at: 1), in: line),
               let value = Int(line[captureRange]) {
                return value
            }
        }
        return 0
    }
}

private extension String {
    /// First ~80 character title-friendly slice of a prompt for thread titles.
    var routerTitle: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled Prompt" }
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }

    /// Default excerpt used when the project hasn't opted into prompt sync.
    var routerExcerpt: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 240 { return trimmed }
        return String(trimmed.prefix(240)) + "…"
    }
}

private extension TimeInterval {
    var formattedDurationSeconds: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: NSNumber(value: self)) ?? "\(self)") + "s"
    }
}
