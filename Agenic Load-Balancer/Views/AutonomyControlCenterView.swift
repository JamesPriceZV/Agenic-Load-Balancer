//
//  AutonomyControlCenterView.swift
//  Agenic Load-Balancer
//
//  Phase 7.6: safe goal intake and autonomous plan drafting.
//

import Foundation
import SwiftData
import SwiftUI

struct AutonomyControlCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("Agenic.allowToolCalling") private var defaultAllowToolCalling = true
    @AppStorage("Agenic.allowShellTools") private var defaultAllowShellTools = true
    @AppStorage("Agenic.allowNetworkSearch") private var defaultAllowNetworkSearch = false
    @AppStorage("Agenic.allowFilesystemWrites") private var defaultAllowFilesystemWrites = true
    @AppStorage("Agenic.defaultWorkingPath") private var appDefaultWorkingPath = ""
    @AppStorage("Agenic.defaultTemporaryPath") private var appDefaultTemporaryPath = ""
    @AppStorage("Agenic.contextCompactionEnabled") private var appContextCompactionEnabled = true
    @AppStorage("Agenic.contextCompactionThresholdTokens") private var appContextCompactionThresholdTokens = 120_000

    let projects: [AgentProject]
    let providers: [AgentProviderProfile]
    let usageEntries: [UsageLedgerEntry]
    let outcomes: [RunOutcomeRecord]
    let coordinationEvents: [CoordinationEventRecord]
    let draftPlan: @Sendable (AutonomousGoalRequest) async throws -> AutonomousPlanDraft
    let validationRunner: any ValidationGateRunning

    @State private var selectedProjectID: String?
    @State private var goalTitle = ""
    @State private var goalDescription = ""
    @State private var level: AutonomyLevel = .proposeActions
    @State private var draft: AutonomousPlanDraft?
    @State private var persistedPlan: PersistedAutonomousPlan?
    @State private var statusText = ""
    @State private var isDrafting = false
    @State private var runningValidationTaskID: String?
    @State private var activeRun: ActiveAutonomyRun?
    @State private var dispatcher = RunDispatcher()

    init(
        projects: [AgentProject],
        providers: [AgentProviderProfile],
        usageEntries: [UsageLedgerEntry],
        outcomes: [RunOutcomeRecord],
        coordinationEvents: [CoordinationEventRecord],
        draftPlan: @escaping @Sendable (AutonomousGoalRequest) async throws -> AutonomousPlanDraft,
        validationRunner: any ValidationGateRunning = ShellValidationGateRunner()
    ) {
        self.projects = projects
        self.providers = providers
        self.usageEntries = usageEntries
        self.outcomes = outcomes
        self.coordinationEvents = coordinationEvents
        self.draftPlan = draftPlan
        self.validationRunner = validationRunner
    }

    private var selectedProject: AgentProject? {
        selectedProjectID.flatMap { id in projects.first { $0.identifier == id } } ?? projects.first
    }

    private var currentPolicy: AutonomyPolicy {
        var policy = AutonomyPolicy.defaultSafe
        policy.level = level
        if let rootPath = selectedProject?.rootPath {
            policy.allowedRootPaths = [rootPath]
        }
        return policy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                goalPanel
                if let draft {
                    planPanel(draft)
                }
                syncPanel
            }
            .padding(24)
        }
        .sheet(item: $activeRun) { active in
            ApprovalSheetView(
                plan: active.plan,
                dispatcher: dispatcher,
                allowsConsoleHide: false,
                onClose: {
                    let taskID = active.taskID
                    activeRun = nil
                    finalizeRunTask(taskID)
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Autonomy")
                .font(.largeTitle.weight(.semibold))
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var goalPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Project", selection: $selectedProjectID) {
                    Text("First Project").tag(String?.none)
                    ForEach(projects, id: \.identifier) { project in
                        Text(project.name).tag(Optional(project.identifier))
                    }
                }
                .frame(maxWidth: 360)

                Picker("Level", selection: $level) {
                    ForEach(AutonomyLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .frame(maxWidth: 280)
            }

            TextField("Goal", text: $goalTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $goalDescription)
                .font(.body)
                .frame(minHeight: 140)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.35), lineWidth: 1)
                )

            Button {
                Task { await createDraft() }
            } label: {
                Label(isDrafting ? "Drafting" : "Draft & Save Plan", systemImage: "list.bullet.clipboard")
            }
            .disabled(isDrafting || goalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func planPanel(_ draft: AutonomousPlanDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.summary)
                .font(.headline)
                .textSelection(.enabled)
            if let persistedPlan {
                Label("Saved plan \(persistedPlan.planID.prefix(8)) · \(persistedPlan.taskIDsByTitle.count) task(s)", systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            ForEach(draft.tasks) { task in
                taskRow(task)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func taskRow(_ task: AutonomousTaskDraft) -> some View {
        let decision = evaluate(task)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(task.title, systemImage: icon(for: task.mode))
                    .font(.headline)
                Spacer()
                Text(task.mode.label)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }
            Text(task.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            if !task.dependencyTitles.isEmpty {
                Label(task.dependencyTitles.joined(separator: ", "), systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let validationCommand = task.validationCommand {
                Label(validationCommand, systemImage: "checkmark.seal")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Label(decision.message, systemImage: decisionIcon(decision))
                .font(.caption.weight(.medium))
                .foregroundStyle(decisionColor(decision))
            taskActions(task: task, decision: decision)
        }
        .padding(12)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func taskActions(task: AutonomousTaskDraft, decision: AutonomyPolicyDecision) -> some View {
        if let taskID = persistedPlan?.taskIDsByTitle[task.title] {
            HStack(spacing: 8) {
                Button {
                    Task { await prepareRun(for: task, taskID: taskID) }
                } label: {
                    Label("Review Run", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDenied(decision) || providers.isEmpty || activeRun != nil)

                if let command = task.validationCommand {
                    Button {
                        Task { await runValidation(taskID: taskID, command: command) }
                    } label: {
                        Label(
                            runningValidationTaskID == taskID ? "Running Validation" : "Run Validation",
                            systemImage: "terminal"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDenied(decision) || runningValidationTaskID != nil)
                }
            }
            .font(.caption)
        } else {
            Label("Save the draft before dispatching or validating tasks.", systemImage: "tray.and.arrow.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var syncPanel: some View {
        let health = MachineSyncCoordinator().health(
            machineID: Host.current().localizedName ?? "local",
            displayName: Host.current().localizedName ?? "This Mac",
            lastSeenAt: Date()
        )
        return VStack(alignment: .leading, spacing: 10) {
            Text("Machine Sync")
                .font(.headline)
            Label(health.detail, systemImage: "desktopcomputer.and.macbook")
                .foregroundStyle(.secondary)
            Text(health.status.rawValue)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @MainActor
    private func createDraft() async {
        isDrafting = true
        statusText = ""
        defer { isDrafting = false }

        let request = AutonomousGoalRequest(
            title: goalTitle,
            goalDescription: goalDescription,
            projectID: selectedProject?.identifier,
            projectRootPath: selectedProject?.rootPath,
            autonomyPolicy: currentPolicy
        )

        do {
            let nextDraft = try await draftPlan(request)
            let persisted = try AutonomyPersistence.persistDraftPlan(
                request: request,
                draft: nextDraft,
                modelContext: modelContext
            )
            draft = nextDraft
            persistedPlan = persisted
            await AppServices.cloudSync.recordLocalSave()
            statusText = "Draft saved to SwiftData as plan \(persisted.planID.prefix(8))."
        } catch {
            draft = nil
            persistedPlan = nil
            statusText = error.localizedDescription
        }
    }

    private func evaluate(_ task: AutonomousTaskDraft) -> AutonomyPolicyDecision {
        return AutonomyPolicyEvaluator().evaluateRun(
            mode: task.mode,
            estimatedCostUSD: 0.01,
            policy: currentPolicy
        )
    }

    @MainActor
    private func prepareRun(for task: AutonomousTaskDraft, taskID: String) async {
        statusText = "Ranking providers for \(task.title)…"
        let prompt = autonomyPrompt(for: task)
        let usage = UsageSnapshotBuilder.build(
            from: usageEntries,
            outcomes: outcomes,
            providers: providers
        )
        let accuracy = AccuracySnapshotBuilder.build(from: outcomes, providers: providers)
        let recommendation = await AppServices.routingRecommendation.recommend(
            prompt: prompt,
            mode: task.mode,
            providers: providers.map { $0.snapshot() },
            usage: usage,
            accuracy: accuracy,
            coordinationEvents: coordinationEvents.map { $0.snapshot() }
        )
        guard let score = recommendation.selected,
              let provider = providers.first(where: { $0.identifier == score.providerID }) else {
            statusText = "No provider is available for \(task.mode.label)."
            return
        }

        do {
            try AutonomyPersistence.markTaskDispatchPrepared(
                taskID: taskID,
                providerID: provider.identifier,
                modelContext: modelContext
            )
            await AppServices.cloudSync.recordLocalSave()
        } catch {
            statusText = error.localizedDescription
            return
        }

        dispatcher.reset()
        activeRun = ActiveAutonomyRun(
            taskID: taskID,
            taskTitle: task.title,
            plan: RunPlan(
                providerSnapshot: provider.snapshot(),
                providerID: provider.identifier,
                providerName: provider.displayName,
                prompt: prompt,
                projectID: selectedProject?.identifier,
                projectName: selectedProject?.name,
                projectRootPath: selectedProject?.rootPath,
                defaultWorkingPath: effectiveWorkingPath,
                temporaryWorkingPath: effectiveTemporaryPath,
                mode: task.mode,
                score: score,
                promptExcerptSyncEnabled: selectedProject?.promptExcerptSyncEnabled ?? false,
                allowToolCalling: selectedProject?.allowToolCalling ?? defaultAllowToolCalling,
                allowShellTools: selectedProject?.allowShellTools ?? defaultAllowShellTools,
                allowNetworkSearch: selectedProject?.allowNetworkSearch ?? defaultAllowNetworkSearch,
                allowFilesystemWrites: selectedProject?.allowFilesystemWrites ?? defaultAllowFilesystemWrites,
                contextCompactionEnabled: selectedProject?.contextCompactionEnabled ?? appContextCompactionEnabled,
                contextCompactionThresholdTokens: selectedProject?.contextCompactionThresholdTokens ?? appContextCompactionThresholdTokens
            )
        )
        statusText = "Run prepared for \(provider.displayName). Review and approve before it starts."
    }

    private var effectiveWorkingPath: String? {
        let projectPath = selectedProject?.defaultWorkingPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let projectPath, !projectPath.isEmpty { return projectPath }
        let appPath = appDefaultWorkingPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appPath.isEmpty { return appPath }
        return selectedProject?.rootPath
    }

    private var effectiveTemporaryPath: String? {
        let projectPath = selectedProject?.temporaryWorkingPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let projectPath, !projectPath.isEmpty { return projectPath }
        let appPath = appDefaultTemporaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return appPath.isEmpty ? nil : appPath
    }

    @MainActor
    private func runValidation(taskID: String, command: String) async {
        runningValidationTaskID = taskID
        statusText = "Running validation gate…"
        defer { runningValidationTaskID = nil }

        do {
            let result = try await AutonomyPersistence.runValidationGate(
                taskID: taskID,
                command: command,
                workingDirectory: selectedProject?.rootPath,
                policy: currentPolicy,
                runner: validationRunner,
                modelContext: modelContext
            )
            await AppServices.cloudSync.recordLocalSave()
            statusText = result.passed ? "Validation passed." : "Validation failed with exit \(result.exitCode)."
        } catch {
            statusText = error.localizedDescription
        }
    }

    @MainActor
    private func finalizeRunTask(_ taskID: String) {
        let status: CoordinationStatus?
        let detail: String
        switch dispatcher.status {
        case .succeeded:
            status = .completed
            detail = "Approval-gated run succeeded."
        case .failed:
            status = .conflict
            detail = "Approval-gated run failed: \(dispatcher.lastError ?? "see run console")."
        case .cancelled:
            status = .cancelled
            detail = "Approval-gated run was cancelled."
        case .idle, .preparing, .running:
            status = nil
            detail = ""
        }
        guard let status else { return }
        do {
            try AutonomyPersistence.updateTaskStatus(
                taskID: taskID,
                status: status,
                detail: detail,
                modelContext: modelContext
            )
            statusText = detail
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func autonomyPrompt(for task: AutonomousTaskDraft) -> String {
        """
        Goal: \(goalTitle)

        \(goalDescription)

        Autonomy task:
        \(task.title)

        \(task.detail)
        """
    }

    private func isDenied(_ decision: AutonomyPolicyDecision) -> Bool {
        if case .denied = decision { return true }
        return false
    }

    private func icon(for mode: AgentExecutionMode) -> String {
        switch mode {
        case .recommendOnly: "wand.and.stars"
        case .readReview: "doc.text.magnifyingglass"
        case .planOnly: "list.bullet.rectangle"
        case .implementation: "hammer"
        case .repairDebug: "stethoscope"
        case .testBuild: "checkmark.seal"
        case .commitPushCheckpoint: "arrow.up.doc"
        }
    }

    private func decisionIcon(_ decision: AutonomyPolicyDecision) -> String {
        switch decision {
        case .allowed: "checkmark.circle.fill"
        case .requiresApproval: "hand.raised.fill"
        case .denied: "xmark.octagon.fill"
        }
    }

    private func decisionColor(_ decision: AutonomyPolicyDecision) -> Color {
        switch decision {
        case .allowed: .green
        case .requiresApproval: .orange
        case .denied: .red
        }
    }
}

private struct ActiveAutonomyRun: Identifiable {
    let taskID: String
    let taskTitle: String
    let plan: RunPlan

    var id: String { taskID }
}
