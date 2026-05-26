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
    let defaultWorkingPath: String?
    let temporaryWorkingPath: String?
    let mode: AgentExecutionMode
    let score: RoutingScoreBreakdown
    let promptExcerptSyncEnabled: Bool
    let allowToolCalling: Bool
    let allowShellTools: Bool
    let allowNetworkSearch: Bool
    let allowFilesystemWrites: Bool
    let contextCompactionEnabled: Bool
    let contextCompactionThresholdTokens: Int
    /// Sprint O.1: optional handle to the parent run when this plan is
    /// itself the resume of a continuation chain. Default `nil` so the
    /// originating run path is unchanged.
    let continuationContext: RunContinuationContext?

    init(
        providerSnapshot: AgentProviderSnapshot,
        providerID: String,
        providerName: String,
        prompt: String,
        projectID: String?,
        projectName: String?,
        projectRootPath: String?,
        defaultWorkingPath: String? = nil,
        temporaryWorkingPath: String? = nil,
        mode: AgentExecutionMode,
        score: RoutingScoreBreakdown,
        promptExcerptSyncEnabled: Bool,
        allowToolCalling: Bool = true,
        allowShellTools: Bool = true,
        allowNetworkSearch: Bool = false,
        allowFilesystemWrites: Bool = true,
        contextCompactionEnabled: Bool = true,
        contextCompactionThresholdTokens: Int = 120_000,
        continuationContext: RunContinuationContext? = nil
    ) {
        self.providerSnapshot = providerSnapshot
        self.providerID = providerID
        self.providerName = providerName
        self.prompt = prompt
        self.projectID = projectID
        self.projectName = projectName
        self.projectRootPath = projectRootPath
        self.defaultWorkingPath = defaultWorkingPath
        self.temporaryWorkingPath = temporaryWorkingPath
        self.mode = mode
        self.score = score
        self.promptExcerptSyncEnabled = promptExcerptSyncEnabled
        self.allowToolCalling = allowToolCalling
        self.allowShellTools = allowShellTools
        self.allowNetworkSearch = allowNetworkSearch
        self.allowFilesystemWrites = allowFilesystemWrites
        self.contextCompactionEnabled = contextCompactionEnabled
        self.contextCompactionThresholdTokens = contextCompactionThresholdTokens
        self.continuationContext = continuationContext
    }
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

    /// Phase 7.2: status of the on-device AI run summarizer. Independent
    /// of the run's own status — a failed summary must NEVER degrade a
    /// successful run.
    enum AISummaryStatus: Sendable, Equatable {
        case notRequested
        case pending
        case unavailable(reason: String)
        case succeeded(summary: RunSummary)
        case failed(reason: String)

        var label: String {
            switch self {
            case .notRequested: "—"
            case .pending: "Summarising…"
            case .unavailable(let reason): "Unavailable: \(reason)"
            case .succeeded: "Summary ready"
            case .failed(let reason): "Summary failed: \(reason)"
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
    private(set) var cachedPromptTokens: Int = 0
    private(set) var reasoningTokens: Int = 0
    private(set) var preflightStartedAt: Date?
    private(set) var preflightEndedAt: Date?
    private(set) var preprocessingSeconds: Double = 0
    private(set) var checkpointStatus: CheckpointStatus = .notRequested
    private(set) var preflightExcerpt: String?
    private(set) var preflightTokenEstimate: TokenBudgetEstimate?
    private(set) var continuationPlan: RunContinuationPlan?
    private(set) var currentPlan: RunPlan?
    /// Phase 7.2: live AI summary state, surfaced to the approval sheet.
    private(set) var aiSummaryStatus: AISummaryStatus = .notRequested

    // MARK: Internal collaborators (excluded from observation tracking)
    @ObservationIgnored private let runner: AgentRunning
    @ObservationIgnored private let adapterFactory: @Sendable (String, ProviderCommandProfileSnapshot?) -> AgentCLIAdapter
    @ObservationIgnored private let coordinationActor: ProjectCoordinationActor
    @ObservationIgnored private let cloudSync: CloudSyncCoordinator
    @ObservationIgnored private let gitCheckpoint: GitCheckpointing
    @ObservationIgnored private let summarizer: any RunSummarizing
    @ObservationIgnored private let now: @Sendable () -> Date

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var activeOutcome: RunOutcomeRecord?
    @ObservationIgnored private var activeUsage: UsageLedgerEntry?
    @ObservationIgnored private var activeCoordination: CoordinationEventRecord?
    @ObservationIgnored private var userCancelRequested: Bool = false

    init(
        runner: AgentRunning = CompositeAgentRunner(),
        adapterFactory: @escaping @Sendable (String, ProviderCommandProfileSnapshot?) -> AgentCLIAdapter = { id, profile in
            AgentAdapterFactory.makeAdapter(providerID: id, commandProfile: profile)
        },
        coordinationActor: ProjectCoordinationActor = AppServices.coordination,
        cloudSync: CloudSyncCoordinator = AppServices.cloudSync,
        gitCheckpoint: GitCheckpointing = AppServices.gitCheckpoint,
        summarizer: any RunSummarizing = RunSummarizerFactory.makeDefault(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runner = runner
        self.adapterFactory = adapterFactory
        self.coordinationActor = coordinationActor
        self.cloudSync = cloudSync
        self.gitCheckpoint = gitCheckpoint
        self.summarizer = summarizer
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
        cachedPromptTokens = 0
        reasoningTokens = 0
        preflightStartedAt = nil
        preflightEndedAt = nil
        preprocessingSeconds = 0
        checkpointStatus = .notRequested
        preflightExcerpt = nil
        preflightTokenEstimate = nil
        continuationPlan = nil
        currentPlan = nil
        aiSummaryStatus = .notRequested
        activeOutcome = nil
        activeUsage = nil
        activeCoordination = nil
        userCancelRequested = false
    }

    /// Persist approval records and start streaming the underlying CLI.
    /// Errors at this stage (missing executable, mode mismatch) are persisted
    /// as a failed run rather than being thrown, so the sheet can render the
    /// failure inline alongside the originally-approved command preview.
    ///
    /// `agentNotesExcerpt` is the current on-disk fallback excerpt (or `nil`
    /// when the project has no AgentNotes file yet). When
    /// `agentNotesPreflightSummary` is supplied, its prompt injection text is
    /// preferred so the agent sees only the prompt-relevant active claims.
    func dispatch(
        plan: RunPlan,
        agentNotesExcerpt: String? = nil,
        agentNotesPreflightSummary: AgentNotesPreflightSummary? = nil,
        modelContext: ModelContext
    ) {
        reset()
        status = .preparing
        currentPlan = plan
        let preflightStart = now()
        preflightStartedAt = preflightStart
        let rawPreflightPromptText = agentNotesPreflightSummary?.promptInjectionText ?? agentNotesExcerpt
        let workspacePolicy = Self.workspacePolicyPrompt(for: plan)
        let preflightBudget = TokenBudgetEstimator.preparePreflightContext(
            userPrompt: plan.prompt,
            agentNotesExcerpt: rawPreflightPromptText,
            workspacePolicy: workspacePolicy,
            projectRootPath: Self.effectiveWorkingPath(for: plan),
            providerID: plan.providerID,
            contextCompactionEnabled: plan.contextCompactionEnabled,
            thresholdTokens: plan.contextCompactionThresholdTokens
        )
        let preflightPromptText = preflightBudget.agentNotesExcerpt
        preflightExcerpt = preflightPromptText
        preflightTokenEstimate = preflightBudget.estimate
        appendSystem("Approved \(plan.providerName) for \(plan.mode.label).")
        appendSystem("Context budget: \(preflightBudget.estimate.summary)")
        if let compactionNote = preflightBudget.compactionNote, preflightBudget.didCompact {
            appendSystem(compactionNote)
        }
        if let agentNotesPreflightSummary {
            appendSystem("AgentNotes intelligent preflight injected (\(preflightPromptText?.count ?? agentNotesPreflightSummary.promptInjectionText.count) chars).")
        } else if preflightPromptText?.isEmpty == false {
            appendSystem("AgentNotes preflight injected (\(preflightPromptText?.count ?? 0) chars).")
        }

        let profile = Self.fetchEnabledCommandProfile(
            providerID: plan.providerID,
            in: modelContext
        )
        let adapter = adapterFactory(plan.providerID, profile)

        let promptForCommand = Self.composeCommandPrompt(
            userPrompt: plan.prompt,
            agentNotesExcerpt: preflightPromptText,
            workspacePolicy: workspacePolicy
        )

        let command: AgentCommand
        do {
            let baseCommand = try adapter.buildCommand(
                prompt: promptForCommand,
                projectPath: Self.effectiveWorkingPath(for: plan),
                mode: plan.mode,
                provider: plan.providerSnapshot
            )
            command = Self.applyingWorkspaceEnvironment(to: baseCommand, plan: plan)
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
        preflightEndedAt = startedAtTimestamp
        preprocessingSeconds = startedAtTimestamp.timeIntervalSince(preflightStart)

        let records = persistApprovalRecords(
            plan: plan,
            command: command,
            modelContext: modelContext,
            startedAt: startedAtTimestamp,
            preflightEstimate: preflightBudget.estimate
        )
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
                        let classification = self.terminalClassification(for: self.exitCode)
                        self.finalize(
                            plan: plan,
                            modelContext: modelContext,
                            terminal: classification.status,
                            code: self.exitCode,
                            errorMessage: classification.message
                        )
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

            // Phase 7.2: feed the captured stdout/stderr buffer into the
            // on-device run summarizer so the dashboard accuracy/performance
            // signals get measurably better data without regex. Failures
            // here must NEVER degrade the run outcome — the run is already
            // marked .succeeded above; the summary is best-effort metadata.
            if self.status == .succeeded {
                await self.performRunSummarization(plan: plan, modelContext: modelContext)
            }
        }
    }

    /// Build the prompt the agent will actually receive. Embeds the
    /// AgentNotes excerpt above the user's prompt so cross-agent claims are
    /// visible as part of the run's input.
    static func composeCommandPrompt(
        userPrompt: String,
        agentNotesExcerpt: String?,
        workspacePolicy: String? = nil
    ) -> String {
        let excerpt = agentNotesExcerpt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let policy = workspacePolicy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var sections: [String] = []
        if !policy.isEmpty {
            sections.append("""
            Workspace policy for this run:
            \(policy)
            """)
        }
        if !excerpt.isEmpty {
            sections.append("""
            Active AgentNotes excerpt (read-only, latest snapshot from disk):
            \(excerpt)
            """)
        }
        sections.append(userPrompt)
        return sections.joined(separator: "\n---\n")
    }

    static func effectiveWorkingPath(for plan: RunPlan) -> String? {
        let override = plan.defaultWorkingPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty {
            return override
        }
        return plan.projectRootPath
    }

    static func workspacePolicyPrompt(for plan: RunPlan) -> String {
        let workingPath = effectiveWorkingPath(for: plan) ?? "provider default"
        let tempPath = plan.temporaryWorkingPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tempLine = tempPath?.isEmpty == false ? tempPath! : "provider default"
        let compaction = plan.contextCompactionEnabled
            ? "Enabled near \(plan.contextCompactionThresholdTokens.formatted()) tokens."
            : "Disabled for this workspace."
        return """
        Working path: \(workingPath)
        Temporary path: \(tempLine)
        Tool calling allowed: \(plan.allowToolCalling ? "yes" : "no")
        Shell tools allowed: \(plan.allowShellTools ? "yes" : "no")
        Network search allowed: \(plan.allowNetworkSearch ? "yes" : "no")
        Filesystem writes allowed: \(plan.allowFilesystemWrites ? "yes" : "no")
        Context compaction: \(compaction)
        """
    }

    static func applyingWorkspaceEnvironment(to command: AgentCommand, plan: RunPlan) -> AgentCommand {
        var environment = command.environment
        if let temporaryPath = plan.temporaryWorkingPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !temporaryPath.isEmpty {
            try? FileManager.default.createDirectory(
                atPath: temporaryPath,
                withIntermediateDirectories: true
            )
            environment["TMPDIR"] = environment["TMPDIR"] ?? temporaryPath
            environment["AGENIC_TMPDIR"] = temporaryPath
        }
        environment["AGENIC_TOOL_CALLING_ALLOWED"] = plan.allowToolCalling ? "1" : "0"
        environment["AGENIC_SHELL_TOOLS_ALLOWED"] = plan.allowShellTools ? "1" : "0"
        environment["AGENIC_NETWORK_SEARCH_ALLOWED"] = plan.allowNetworkSearch ? "1" : "0"
        environment["AGENIC_FILESYSTEM_WRITES_ALLOWED"] = plan.allowFilesystemWrites ? "1" : "0"

        return AgentCommand(
            id: command.id,
            providerID: command.providerID,
            executablePath: command.executablePath,
            arguments: command.arguments,
            environment: environment,
            workingDirectory: command.workingDirectory,
            standardInput: command.standardInput,
            requiresApproval: command.requiresApproval
        )
    }

    static func summaryBufferCharacterLimit(for plan: RunPlan) -> Int {
        let defaultsValue = UserDefaults.standard.integer(forKey: "Agenic.summaryBufferCharacterLimit")
        let configured = defaultsValue > 0 ? defaultsValue : RunSummaryInput.maxBufferBytes
        guard plan.contextCompactionEnabled else {
            return max(512, min(configured, 24_000))
        }
        let tokenBudgetApprox = max(1_000, plan.contextCompactionThresholdTokens / 48)
        return max(512, min(configured, tokenBudgetApprox, 12_000))
    }

    static func summaryPromptCharacterLimit(for plan: RunPlan) -> Int {
        guard plan.contextCompactionEnabled else {
            return 8_000
        }
        return max(512, min(2_000, plan.contextCompactionThresholdTokens / 96))
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

    /// Phase 7.2: feed the captured stdout/stderr buffer to the run
    /// summarizer and stamp the structured fields onto the active
    /// `RunOutcomeRecord`. Errors are caught and surfaced through
    /// `aiSummaryStatus` — the run itself is NOT marked failed.
    private func performRunSummarization(plan: RunPlan, modelContext: ModelContext) async {
        guard let outcome = activeOutcome else { return }
        aiSummaryStatus = .pending
        appendSystem("Requesting on-device run summary…")

        let stdoutBuffer = capturedLogBuffer(kind: .stdout)
        let stderrBuffer = capturedLogBuffer(kind: .stderr)

        let input = RunSummaryInput(
            prompt: plan.prompt,
            providerID: plan.providerID,
            providerName: plan.providerName,
            mode: plan.mode,
            exitCode: exitCode,
            durationSeconds: outcome.durationSeconds,
            standardOutput: stdoutBuffer,
            standardError: stderrBuffer,
            maxBufferCharacters: Self.summaryBufferCharacterLimit(for: plan),
            maxPromptCharacters: Self.summaryPromptCharacterLimit(for: plan)
        )

        do {
            let summary = try await summarizer.summarize(input: input)
            outcome.applyRunSummary(summary, generatedAt: now())
            do {
                try modelContext.save()
            } catch {
                appendSystem("Failed to save AI summary: \(error.localizedDescription)")
            }
            aiSummaryStatus = .succeeded(summary: summary)
            appendSystem("AI summary: \(summary.oneLineDescription)")

            let cloudSyncRef = cloudSync
            Task { await cloudSyncRef.recordLocalSave() }
        } catch let error as RunSummaryError {
            switch error {
            case .unavailable(let reason):
                aiSummaryStatus = .unavailable(reason: reason)
                appendSystem("AI summary skipped — \(reason)")
            case .generationFailed(let reason):
                aiSummaryStatus = .failed(reason: reason)
                appendSystem("AI summary failed — \(reason)")
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            aiSummaryStatus = .failed(reason: message)
            appendSystem("AI summary failed — \(message)")
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
            let classification = terminalClassification(for: code)
            finalize(
                plan: plan,
                modelContext: modelContext,
                terminal: classification.status,
                code: code,
                errorMessage: classification.message
            )
        }
    }

    private func terminalClassification(for code: Int32?) -> (status: LiveStatus, message: String?) {
        if userCancelRequested {
            return (.cancelled, nil)
        }

        if let providerFailure = ProviderFailureClassifier.failureMessage(in: logs) {
            return (.failed, providerFailure)
        }

        if let code, code != 0 {
            return (.failed, "Process exited with code \(code).")
        }

        return (.succeeded, nil)
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

    private func capturedLogBuffer(kind: LogLine.Kind) -> String {
        logs
            .filter { $0.kind == kind }
            .map(\.text)
            .joined(separator: "\n")
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
        startedAt: Date,
        preflightEstimate: TokenBudgetEstimate?
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
            startedAt: startedAt,
            contextBudgetSummary: preflightEstimate?.summary,
            continuationTriggerCategory: plan.continuationContext?.triggerCategory.rawValue,
            continuationChainDepth: (plan.continuationContext?.parentChainDepth ?? -1) + 1,
            continuationParentRunID: plan.continuationContext?.parentRunID
        )
        let usage = UsageLedgerEntry(
            providerID: plan.providerID,
            runID: outcome.runID,
            promptTokens: preflightEstimate?.totalInputTokens ?? 0,
            completionTokens: 0,
            cachedPromptTokens: 0,
            reasoningTokens: 0,
            callCount: 1,
            estimatedCostUSD: plan.score.estimatedCostUSD,
            durationSeconds: 0,
            preprocessingSeconds: preprocessingSeconds,
            sessionSeconds: 0,
            limitWindow: preflightEstimate?.ledgerLimitWindow ?? "manual",
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
            durationSeconds: 0,
            contextBudgetSummary: preflightTokenEstimate?.summary
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
        let stdoutBuffer = capturedLogBuffer(kind: .stdout)
        let stderrBuffer = capturedLogBuffer(kind: .stderr)
        let runEstimate = TokenBudgetEstimator.estimateRun(
            plan: plan,
            agentNotesExcerpt: preflightExcerpt,
            workspacePolicy: Self.workspacePolicyPrompt(for: plan),
            projectRootPath: Self.effectiveWorkingPath(for: plan),
            standardOutput: stdoutBuffer,
            standardError: stderrBuffer,
            cachedPromptTokens: cachedPromptTokens,
            outputTokens: completionTokens,
            reasoningTokens: reasoningTokens
        )
        preflightTokenEstimate = runEstimate

        if let outcome = activeOutcome {
            outcome.endedAt = endTimestamp
            outcome.durationSeconds = durationSeconds
            outcome.contextBudgetSummary = runEstimate.summary
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
                let trigger = ProviderFailureClassifier.categorize(errorMessage: errorMessage)
                if trigger != .unknown {
                    let policy = ProviderContinuationPolicy.defaultPolicy(for: plan.providerID)
                    let parentChainDepth = plan.continuationContext?.parentChainDepth ?? 0
                    let decision = TokenBudgetEstimator.prepareContinuation(
                        plan: plan,
                        parentRunID: outcome.runID,
                        parentChainDepth: parentChainDepth,
                        triggerCategory: trigger,
                        errorMessage: errorMessage,
                        standardOutput: stdoutBuffer,
                        standardError: stderrBuffer,
                        estimate: runEstimate,
                        policy: policy,
                        clock: now
                    )
                    switch decision {
                    case .prepared(let continuation, let requiresApproval, let appliedPolicy):
                        continuationPlan = continuation
                        outcome.continuationSummary = continuation.summary
                        outcome.continuationPrompt = continuation.prompt
                        outcome.continuationTriggerCategory = continuation.triggerCategory
                        outcome.continuationChainDepth = max(
                            outcome.continuationChainDepth,
                            continuation.chainDepth
                        )
                        outcome.continuationRequiresApproval = requiresApproval
                        outcome.continuationWorkspaceExcerptCount = continuation.workspaceExcerptCount
                        outcome.continuationPolicyNote = appliedPolicy.resumeNote
                        appendSystem(
                            "Continuation prepared via \(appliedPolicy.displayName) policy (depth \(continuation.chainDepth), \(requiresApproval ? "approval-gated" : "auto-resume ready"), \(continuation.estimatedResumeTokens.formatted()) estimated tokens, \(continuation.workspaceExcerptCount) source excerpt(s))."
                        )
                    case .notEligible(let reason):
                        outcome.continuationTriggerCategory = trigger.rawValue
                        outcome.continuationPolicyNote = reason
                        appendSystem("Continuation not offered: \(reason)")
                    }
                }
            }
        }

        if let outcome = activeOutcome {
            let segments = RunTranscriptSegmenter.segments(
                runID: outcome.runID,
                providerID: plan.providerID,
                projectID: plan.projectID,
                logs: logs,
                createdAt: endTimestamp
            )
            for segment in segments {
                modelContext.insert(RunTranscriptSegmentRecord(
                    runID: segment.runID,
                    providerID: segment.providerID,
                    projectID: segment.projectID,
                    segmentIndex: segment.segmentIndex,
                    kind: segment.kind,
                    text: segment.text,
                    tokenEstimate: segment.tokenEstimate,
                    isCompacted: segment.isCompacted,
                    summary: segment.summary,
                    createdAt: segment.createdAt
                ))
            }
            outcome.transcriptSegmentCount = segments.count
        }

        if let usage = activeUsage {
            let estimatedTokens: (prompt: Int, completion: Int) = {
                if promptTokens > 0 || completionTokens > 0 {
                    return (promptTokens, completionTokens)
                }
                let promptApprox = max(runEstimate.totalInputTokens, 1)
                let completionApprox = max(runEstimate.standardOutputTokens + runEstimate.standardErrorTokens, 0)
                return (promptApprox, completionApprox)
            }()
            usage.promptTokens = estimatedTokens.prompt
            usage.completionTokens = estimatedTokens.completion
            usage.cachedPromptTokens = cachedPromptTokens
            usage.reasoningTokens = reasoningTokens
            usage.durationSeconds = durationSeconds
            usage.preprocessingSeconds = preprocessingSeconds
            usage.sessionSeconds = durationSeconds
            usage.limitWindow = runEstimate.ledgerLimitWindow
        }

        if let coordination = activeCoordination {
            coordination.status = {
                switch terminal {
                case .succeeded: return CoordinationStatus.completed.rawValue
                case .cancelled: return CoordinationStatus.cancelled.rawValue
                case .failed: return CoordinationStatus.conflict.rawValue
                default: return CoordinationStatus.blocked.rawValue
                }
            }()
            if let errorMessage {
                coordination.detail += "\n\(errorMessage)"
                if terminal == .failed {
                    coordination.conflictMarker = errorMessage
                }
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
        cachedPromptTokens += parsed.cachedPrompt
        reasoningTokens += parsed.reasoning
    }
}

/// Best-effort scanner for inline token usage markers emitted by streaming
/// CLIs (Codex, Claude Code, etc.). When a line contains
/// `"prompt_tokens": <n>` / `"completion_tokens": <n>`, Codex-style
/// `"input_tokens": <n>` / `"output_tokens": <n>`, or shell-style pairs,
/// the values are returned. Otherwise zeros are returned and the dispatcher
/// falls back to a character-based estimate.
enum TokenUsageParser {
    static func parse(line: String) -> (prompt: Int, completion: Int, cachedPrompt: Int, reasoning: Int) {
        (
            prompt: extractFirstInt(forKeys: ["prompt_tokens", "input_tokens"], in: line),
            completion: extractFirstInt(forKeys: ["completion_tokens", "output_tokens"], in: line),
            cachedPrompt: extractInt(forKey: "cached_input_tokens", in: line),
            reasoning: extractInt(forKey: "reasoning_output_tokens", in: line)
        )
    }

    private static func extractFirstInt(forKeys keys: [String], in line: String) -> Int {
        for key in keys {
            let value = extractInt(forKey: key, in: line)
            if value > 0 { return value }
        }
        return 0
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

enum ProviderFailureClassifier {
    static func failureMessage(in lines: [RunDispatcher.LogLine]) -> String? {
        let text = lines
            .filter { $0.kind == .stdout || $0.kind == .stderr }
            .map(\.text)
            .joined(separator: "\n")
        guard !text.isEmpty else { return nil }

        let lowercased = text.lowercased()
        if containsContextLimitFailure(lowercased) {
            return "Provider reported that the request exceeded the available context window."
        }
        if containsQuotaFailure(lowercased) {
            return "Provider reported a quota or rate-limit failure."
        }
        if containsStructuredFailureStatus(lowercased) {
            return "Provider reported a failed run in its structured output."
        }
        if let nestedExitCode = firstNonZeroNestedExitCode(in: text) {
            return "Provider reported an inner command failure with exit code \(nestedExitCode)."
        }
        return nil
    }

    /// Sprint O.1: map a failure message (whether built by
    /// `failureMessage(in:)` or supplied by the runner) into a stable
    /// `ContinuationTriggerCategory`. Unknown messages fall back to
    /// `.unknown` so policy callers always have a concrete answer.
    static func categorize(errorMessage: String?) -> ContinuationTriggerCategory {
        guard let errorMessage else { return .unknown }
        let lowercased = errorMessage.lowercased()
        if lowercased.contains("context window") ||
            lowercased.contains("context length") ||
            lowercased.contains("token limit") ||
            lowercased.contains("tokens exceeded") ||
            lowercased.contains("context_length_exceeded") {
            return .contextOverflow
        }
        if lowercased.contains("quota") ||
            lowercased.contains("rate limit") ||
            lowercased.contains("rate_limit") ||
            lowercased.contains("429") {
            return .quotaOrRateLimit
        }
        if lowercased.contains("structured output") ||
            lowercased.contains("failed run in its structured") {
            return .structuredFailure
        }
        if lowercased.contains("inner command failure") ||
            lowercased.contains("nested non-zero") ||
            lowercased.contains("exit code") {
            return .nestedNonZeroExit
        }
        return .unknown
    }

    private static func containsContextLimitFailure(_ text: String) -> Bool {
        let markers = [
            "context window",
            "context length",
            "context_length_exceeded",
            "maximum context",
            "max context",
            "too many tokens",
            "token limit",
            "tokens exceeded",
        ]
        guard markers.contains(where: { text.contains($0) }) else { return false }
        return text.contains("exceed") ||
            text.contains("too many") ||
            text.contains("maximum") ||
            text.contains("limit")
    }

    private static func containsQuotaFailure(_ text: String) -> Bool {
        (text.contains("quota") || text.contains("rate limit") || text.contains("rate_limit"))
            && (text.contains("exceed") || text.contains("exhaust") || text.contains("429"))
    }

    private static func containsStructuredFailureStatus(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        return compact.contains(#""status":"failed""#) ||
            compact.contains(#""status":"error""#) ||
            compact.contains(#""status":"cancelled""#)
    }

    private static func firstNonZeroNestedExitCode(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #""exit_code"\s*:\s*(-?\d+)"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        for match in matches where match.numberOfRanges >= 2 {
            guard let captureRange = Range(match.range(at: 1), in: text),
                  let value = Int(text[captureRange]),
                  value != 0 else {
                continue
            }
            return value
        }
        return nil
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

extension TimeInterval {
    var formattedDurationSeconds: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: NSNumber(value: self)) ?? "\(self)") + "s"
    }
}
