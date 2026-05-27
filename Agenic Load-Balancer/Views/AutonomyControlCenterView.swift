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
    @AppStorage("Agenic.autonomy.maxIterations") private var loopMaxIterations = AutonomyLoopBudgetConfig.defaultMaxIterations
    @AppStorage("Agenic.autonomy.maxValidationFailures") private var loopMaxValidationFailures = AutonomyLoopBudgetConfig.defaultMaxValidationFailures
    @AppStorage("Agenic.autonomy.maxApprovalsBeforeHalt") private var loopMaxApprovalsBeforeHalt = AutonomyLoopBudgetConfig.defaultMaxApprovalsBeforeHalt
    @AppStorage("Agenic.autonomy.retention.maxReportsPerPlan") private var retentionMaxReportsPerPlan = AutonomyLoopReportRetentionPolicy.defaultMaxReportsPerPlan
    @AppStorage("Agenic.autonomy.retention.maxAgeDays") private var retentionMaxAgeDaysOrZero = AutonomyLoopReportRetentionPolicy.defaultMaxAgeDaysStorageValue
    @Query(sort: \AutonomyGoalRecord.updatedAt, order: .reverse) private var autonomyGoals: [AutonomyGoalRecord]
    @Query(sort: \AutonomyTaskRecord.updatedAt, order: .reverse) private var autonomyTasks: [AutonomyTaskRecord]
    @Query private var validationGates: [ValidationGateRecord]
    @Query(sort: \MachinePeerRecord.updatedAt, order: .reverse) private var machinePeers: [MachinePeerRecord]
    @Query(sort: \AutonomousLoopReportRecord.endedAt, order: .reverse) private var loopReports: [AutonomousLoopReportRecord]

    let projects: [AgentProject]
    let providers: [AgentProviderProfile]
    let usageEntries: [UsageLedgerEntry]
    let outcomes: [RunOutcomeRecord]
    let coordinationEvents: [CoordinationEventRecord]
    let snapshots: [CloudSnapshotRecord]
    let draftPlan: @Sendable (AutonomousGoalRequest) async throws -> AutonomousPlanDraft
    let validationRunner: any ValidationGateRunning

    @State private var selectedProjectID: String?
    @State private var goalTitle = ""
    @State private var goalDescription = ""
    @State private var level: AutonomyLevel = .proposeActions
    @State private var trustLane: AutonomyTrustLane = .smallFileEdits
    @State private var draft: AutonomousPlanDraft?
    @State private var persistedPlan: PersistedAutonomousPlan?
    @State private var statusText = ""
    @State private var isDrafting = false
    @State private var runningValidationTaskID: String?
    @State private var activeRun: ActiveAutonomyRun?
    @State private var dispatcher = RunDispatcher()
    @State private var presentedLoopReport: PresentedLoopReport?
    @State private var isRunningLoop = false

    init(
        projects: [AgentProject],
        providers: [AgentProviderProfile],
        usageEntries: [UsageLedgerEntry],
        outcomes: [RunOutcomeRecord],
        coordinationEvents: [CoordinationEventRecord],
        snapshots: [CloudSnapshotRecord],
        draftPlan: @escaping @Sendable (AutonomousGoalRequest) async throws -> AutonomousPlanDraft,
        validationRunner: any ValidationGateRunning = ShellValidationGateRunner()
    ) {
        self.projects = projects
        self.providers = providers
        self.usageEntries = usageEntries
        self.outcomes = outcomes
        self.coordinationEvents = coordinationEvents
        self.snapshots = snapshots
        self.draftPlan = draftPlan
        self.validationRunner = validationRunner
    }

    private var selectedProject: AgentProject? {
        selectedProjectID.flatMap { id in projects.first { $0.identifier == id } } ?? projects.first
    }

    private var currentPolicy: AutonomyPolicy {
        currentLaneTemplate.policy
    }

    private var currentLaneTemplate: AutonomyTrustLaneTemplate {
        AutonomyTrustLaneTemplate(
            lane: trustLane,
            rootPath: selectedProject?.rootPath,
            level: level
        )
    }

    private var latestSnapshot: CloudSnapshotRecord? {
        snapshots
            .filter { $0.status == "available" }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private var latestCheckpoint: CoordinationEventRecord? {
        coordinationEvents
            .filter { event in
                let projectMatches = selectedProject?.identifier == nil || event.projectID == selectedProject?.identifier
                return projectMatches &&
                    (event.status == CoordinationStatus.checkpointed.rawValue || event.commitSHA != nil)
            }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private var selectedGoalIDs: Set<String> {
        let projectID = selectedProject?.identifier
        return Set(
            autonomyGoals
                .filter { goal in
                    guard let projectID else { return true }
                    return goal.projectID == projectID
                }
                .map(\.identifier)
        )
    }

    private var selectedAutonomyTasks: [AutonomyTaskRecord] {
        let goalIDs = selectedGoalIDs
        return autonomyTasks
            .filter { task in
                guard let goalID = task.goalID else { return false }
                return goalIDs.contains(goalID)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selectedValidationGates: [ValidationGateRecord] {
        let taskIDs = Set(selectedAutonomyTasks.map(\.identifier))
        return validationGates.filter { gate in
            guard let taskID = gate.taskID else { return false }
            return taskIDs.contains(taskID)
        }
    }

    private var localMachineHealth: MachineSyncHealth {
        MachineSyncCoordinator().health(
            machineID: Host.current().localizedName ?? "local",
            displayName: Host.current().localizedName ?? "This Mac",
            lastSeenAt: Date()
        )
    }

    private var readiness: AutonomyReadinessSnapshot {
        AutonomyReadinessBuilder().build(
            project: selectedProject,
            providers: providers,
            policy: currentPolicy,
            machineHealth: localMachineHealth,
            tasks: selectedAutonomyTasks,
            validationGates: selectedValidationGates
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 16) {
                            readinessPanel
                            goalPanel
                            if let draft {
                                planPanel(draft)
                            }
                            if !loopReports.isEmpty {
                                loopHistoryPanel
                            }
                        }
                        .frame(minWidth: 460, maxWidth: .infinity, alignment: .topLeading)

                        VStack(alignment: .leading, spacing: 16) {
                            safetyPanel
                            workPanel
                            syncPanel
                        }
                        .frame(minWidth: 360, maxWidth: 460, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        readinessPanel
                        goalPanel
                        if let draft {
                            planPanel(draft)
                        }
                        safetyPanel
                        workPanel
                        syncPanel
                        if !loopReports.isEmpty {
                            loopHistoryPanel
                        }
                    }
                }
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
        .sheet(item: $presentedLoopReport) { presented in
            AutonomyLoopReportDetailView(
                report: presented.report,
                onClose: { presentedLoopReport = nil }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Autonomy")
                    .font(.largeTitle.weight(.semibold))
                Text(statusText.isEmpty ? readiness.nextAction : statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Label(readiness.title, systemImage: readinessIcon(readiness.state))
                .font(.headline)
                .foregroundStyle(readinessColor(readiness.state))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                Gauge(value: Double(readiness.score), in: 0...100) {
                    Text("Readiness")
                } currentValueLabel: {
                    Text("\(readiness.score)")
                        .font(.title3.weight(.bold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(readinessColor(readiness.state))
                .frame(width: 86, height: 86)

                VStack(alignment: .leading, spacing: 6) {
                    Text(readiness.title)
                        .font(.title2.weight(.semibold))
                    Text(readiness.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(readiness.nextAction, systemImage: "arrow.forward.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(readinessColor(readiness.state))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                AutonomyMetricTile(title: "Active", value: "\(readiness.activeTaskCount)", systemImage: "play.circle")
                AutonomyMetricTile(title: "Blocked", value: "\(readiness.blockedTaskCount)", systemImage: "exclamationmark.triangle")
                AutonomyMetricTile(title: "Validated", value: "\(readiness.validationGateCount)", systemImage: "checkmark.seal")
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .overlay(alignment: .topTrailing) {
                    LinearGradient(
                        colors: [
                            readinessColor(readiness.state).opacity(0.28),
                            Color.teal.opacity(0.08),
                            Color.clear,
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(readinessColor(readiness.state).opacity(0.35), lineWidth: 1)
        )
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

                Picker("Lane", selection: $trustLane) {
                    ForEach(AutonomyTrustLane.allCases) { lane in
                        Label(lane.label, systemImage: lane.systemImage).tag(lane)
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
                Label(isDrafting ? "Drafting" : "Draft & Save Plan", systemImage: "sparkles.rectangle.stack")
            }
            .disabled(isDrafting || goalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func planPanel(_ draft: AutonomousPlanDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.summary)
                        .font(.headline)
                        .textSelection(.enabled)
                    if let persistedPlan {
                        Label("Plan \(persistedPlan.planID.prefix(8)) · \(persistedPlan.taskIDsByTitle.count) task(s)", systemImage: "internaldrive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                Text(readiness.canPrepareAutonomousRuns ? "Gated" : "Held")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readiness.canPrepareAutonomousRuns ? .green : .orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
            }

            ForEach(draft.tasks) { task in
                taskRow(task)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func taskRow(_ task: AutonomousTaskDraft) -> some View {
        let review = safetyReview(for: task)
        let decision = review.decision
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
            VStack(alignment: .leading, spacing: 5) {
                Label("Why this is safe", systemImage: "shield.checkered")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(review.reasons.prefix(3), id: \.self) { reason in
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let stopReason = review.stopReason {
                    Label(stopReason, systemImage: "hand.raised.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            taskActions(task: task, decision: decision)
        }
        .padding(12)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
    }

    private var safetyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Safety Contract")
                .font(.headline)
            laneSummaryPanel
            ForEach(readiness.checks) { check in
                ReadinessCheckRow(check: check)
            }
            loopBudgetSection
            loopRetentionSection
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Sprint Q.10: bound the persisted scheduler-report store so a
    /// long-running developer doesn't accumulate thousands of rows.
    /// Always preserves the most recent report per plan even when
    /// retention thresholds drop other reports.
    private var loopRetentionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Loop Retention", systemImage: "tray.full")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(resolvedRetentionPolicy.summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("Autonomy.LoopRetention.Summary")
            }
            Stepper(
                value: $retentionMaxReportsPerPlan,
                in: AutonomyLoopReportRetentionPolicy.minMaxReportsPerPlan...AutonomyLoopReportRetentionPolicy.maxMaxReportsPerPlan
            ) {
                HStack {
                    Text("Max reports per plan")
                    Spacer()
                    Text("\(retentionMaxReportsPerPlan)")
                        .font(.callout.monospacedDigit())
                }
            }
            .accessibilityIdentifier("Autonomy.LoopRetention.MaxReportsPerPlan")
            Stepper(
                value: $retentionMaxAgeDaysOrZero,
                in: AutonomyLoopReportRetentionPolicy.minMaxAgeDaysStorageValue...AutonomyLoopReportRetentionPolicy.maxMaxAgeDaysStorageValue
            ) {
                HStack {
                    Text("Max age (days, 0 = no limit)")
                    Spacer()
                    Text(retentionMaxAgeDaysOrZero == 0 ? "off" : "\(retentionMaxAgeDaysOrZero)")
                        .font(.callout.monospacedDigit())
                }
            }
            .accessibilityIdentifier("Autonomy.LoopRetention.MaxAgeDays")
            Text("Retention always preserves the most recent report per plan, then drops anything beyond the configured caps after the next loop walk.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private var resolvedRetentionPolicy: AutonomyLoopReportRetentionPolicy {
        AutonomyLoopReportRetentionPolicy.clamped(
            maxReportsPerPlan: retentionMaxReportsPerPlan,
            maxAgeDaysOrZero: retentionMaxAgeDaysOrZero
        )
    }

    /// Sprint Q.8: user-configurable scheduler caps. Defaults match
    /// `AutonomousLoopBudget.default`; UI clamps via
    /// `AutonomyLoopBudgetConfig` so out-of-range writes can't bypass
    /// the safety bounds.
    private var loopBudgetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Loop Budget", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(resolvedBudgetConfig.summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("Autonomy.LoopBudget.Summary")
            }
            Stepper(
                value: $loopMaxIterations,
                in: AutonomyLoopBudgetConfig.minMaxIterations...AutonomyLoopBudgetConfig.maxMaxIterations
            ) {
                HStack {
                    Text("Max iterations")
                    Spacer()
                    Text("\(loopMaxIterations)")
                        .font(.callout.monospacedDigit())
                }
            }
            .accessibilityIdentifier("Autonomy.LoopBudget.MaxIterations")
            Stepper(
                value: $loopMaxValidationFailures,
                in: AutonomyLoopBudgetConfig.minMaxValidationFailures...AutonomyLoopBudgetConfig.maxMaxValidationFailures
            ) {
                HStack {
                    Text("Max validation failures")
                    Spacer()
                    Text("\(loopMaxValidationFailures)")
                        .font(.callout.monospacedDigit())
                }
            }
            .accessibilityIdentifier("Autonomy.LoopBudget.MaxValidationFailures")
            Stepper(
                value: $loopMaxApprovalsBeforeHalt,
                in: AutonomyLoopBudgetConfig.minMaxApprovalsBeforeHalt...AutonomyLoopBudgetConfig.maxMaxApprovalsBeforeHalt
            ) {
                HStack {
                    Text("Max approvals before halt")
                    Spacer()
                    Text("\(loopMaxApprovalsBeforeHalt)")
                        .font(.callout.monospacedDigit())
                }
            }
            .accessibilityIdentifier("Autonomy.LoopBudget.MaxApprovalsBeforeHalt")
            Text("Bounds clamp out-of-range values to safe maxima before the scheduler runs.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private var resolvedBudgetConfig: AutonomyLoopBudgetConfig {
        AutonomyLoopBudgetConfig.clamped(
            maxIterations: loopMaxIterations,
            maxValidationFailures: loopMaxValidationFailures,
            maxApprovalsBeforeHalt: loopMaxApprovalsBeforeHalt
        )
    }

    private var laneSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(trustLane.label, systemImage: trustLane.systemImage)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(currentPolicy.networkAccessAllowed ? "Network gated" : "No network")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(currentPolicy.networkAccessAllowed ? .orange : .secondary)
            }
            Text(trustLane.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Label(latestSnapshot == nil ? "No snapshot" : "Snapshot ready", systemImage: "camera.metering.matrix")
                Label(latestCheckpoint == nil ? "No checkpoint" : "Checkpoint ready", systemImage: "arrow.up.doc")
            }
            .font(.caption)
            .foregroundStyle((latestSnapshot == nil && latestCheckpoint == nil) ? .orange : .green)
            if !currentPolicy.validationCommands.isEmpty {
                Text(currentPolicy.validationCommands.first ?? "")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private var workPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Autonomous Work")
                    .font(.headline)
                Spacer()
                Text("\(selectedAutonomyTasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }
            if selectedAutonomyTasks.isEmpty {
                Label("No saved autonomous tasks", systemImage: "tray")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(selectedAutonomyTasks.prefix(6)), id: \.identifier) { task in
                    StoredAutonomyTaskRow(
                        task: task,
                        goalTitle: goalTitle(for: task),
                        providerName: providerName(for: task.assignedProviderID)
                    )
                }
                runLoopButton
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Sprint Q.8: invoke the autonomous loop scheduler against the
    /// persisted plan. The scheduler only runs validation gates and
    /// completes advisory tasks; it halts on the first approval-required
    /// task so the dispatcher still owns mutating execution. The user-
    /// configured budget caps come from `loopBudgetSection`.
    @ViewBuilder
    private var runLoopButton: some View {
        let disabled = persistedPlan == nil
            || (selectedProject?.rootPath ?? "").isEmpty
            || runningValidationTaskID != nil
            || isRunningLoop
            || activeRun != nil
        Button {
            Task { await runAutonomousLoop() }
        } label: {
            Label(
                isRunningLoop ? "Running Loop…" : "Run Loop",
                systemImage: isRunningLoop ? "arrow.triangle.2.circlepath" : "play.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(disabled)
        .help("Walk the persisted plan with the configured loop budget, running validation gates and halting on the first approval.")
        .accessibilityIdentifier("Autonomy.LoopBudget.RunLoop")
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Machine Sync")
                    .font(.headline)
                Spacer()
                Text(localMachineHealth.status.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(readinessColor(readinessState(for: localMachineHealth.status)))
            }
            Label(localMachineHealth.detail, systemImage: "desktopcomputer.and.macbook")
                .foregroundStyle(.secondary)
            if machinePeers.isEmpty {
                Text("Local peer only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(machinePeers.prefix(3), id: \.identifier) { peer in
                    HStack {
                        Label(peer.displayName, systemImage: "macbook.and.iphone")
                        Spacer()
                        Text(peer.syncStatus)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Sprint Q.5: render persisted scheduler reports so the user can
    /// see the most recent loop walk, its halt reason, and a compact
    /// iteration timeline. Reports are sorted by `endedAt` descending.
    private var loopHistoryPanel: some View {
        let recent = Array(loopReports.prefix(3))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Loop History")
                    .font(.headline)
                Spacer()
                Text("\(loopReports.count) report(s)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("Autonomy.LoopHistory.Header")
            ForEach(recent, id: \.identifier) { report in
                Button {
                    presentedLoopReport = PresentedLoopReport(report: report)
                } label: {
                    AutonomyLoopReportRow(report: report)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("Autonomy.LoopHistory.Open.\(report.identifier)")
            }
            if loopReports.count > recent.count {
                Text("+\(loopReports.count - recent.count) older")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("Autonomy.LoopHistory")
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
            policy: currentPolicy,
            evidence: evidence(for: task)
        )
    }

    private func safetyReview(for task: AutonomousTaskDraft) -> AutonomySafetyReview {
        AutonomyPolicyEvaluator().safetyReview(
            title: task.title,
            mode: task.mode,
            estimatedCostUSD: 0.01,
            policy: currentPolicy,
            evidence: evidence(for: task)
        )
    }

    private func evidence(for task: AutonomousTaskDraft) -> AutonomySafetyEvidence {
        AutonomySafetyEvidence(
            hasRecentSnapshot: latestSnapshot != nil,
            hasRecentCheckpoint: latestCheckpoint != nil,
            candidateChangedFileCount: task.mode.isMutatingAutonomyMode ? 1 : 0,
            command: task.validationCommand,
            networkRequested: false
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
        let reliability = ProviderReliabilityBuilder.build(providers: providers, outcomes: outcomes)
        let recommendation = await AppServices.routingRecommendation.recommend(
            prompt: prompt,
            mode: task.mode,
            providers: providers.map { $0.snapshot() },
            usage: usage,
            accuracy: accuracy,
            reliability: reliability,
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

    /// Sprint Q.8: invoke the autonomous loop scheduler against the
    /// persisted plan with the user-configured budget. The scheduler
    /// only runs validation gates and completes advisory tasks; it
    /// halts on the first approval-required / denied / cap / deadlock
    /// condition, so this entry point is safe to expose alongside the
    /// existing per-task `Run Validation` button.
    @MainActor
    private func runAutonomousLoop() async {
        guard let persistedPlan, let projectRoot = selectedProject?.rootPath, !projectRoot.isEmpty else {
            statusText = "Persist a plan and select a project root before running the loop."
            return
        }
        isRunningLoop = true
        statusText = "Running autonomous loop…"
        defer { isRunningLoop = false }

        let scheduler = AutonomousLoopScheduler()
        let report = await scheduler.run(
            plan: persistedPlan,
            policy: currentPolicy,
            projectRootPath: projectRoot,
            validationRunner: validationRunner,
            budget: resolvedBudgetConfig.asBudget,
            modelContext: modelContext
        )
        let pruned = AutonomousLoopPersistence.applyRetention(
            policy: resolvedRetentionPolicy,
            modelContext: modelContext
        )
        await AppServices.cloudSync.recordLocalSave()
        let suffix = pruned > 0 ? " (pruned \(pruned) older report\(pruned == 1 ? "" : "s"))" : ""
        statusText = "Loop halted: \(report.haltReason.label)\(suffix)"
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

    private func goalTitle(for task: AutonomyTaskRecord) -> String? {
        guard let goalID = task.goalID else { return nil }
        return autonomyGoals.first(where: { $0.identifier == goalID })?.title
    }

    private func providerName(for providerID: String?) -> String? {
        guard let providerID else { return nil }
        return providers.first(where: { $0.identifier == providerID })?.displayName
    }

    private func readinessIcon(_ state: AutonomyReadinessState) -> String {
        switch state {
        case .ready: "checkmark.shield.fill"
        case .caution: "shield.lefthalf.filled.badge.checkmark"
        case .blocked: "shield.slash.fill"
        }
    }

    private func readinessColor(_ state: AutonomyReadinessState) -> Color {
        switch state {
        case .ready: .green
        case .caution: .orange
        case .blocked: .red
        }
    }

    private func readinessState(for syncStatus: MachineSyncStatus) -> AutonomyReadinessState {
        switch syncStatus {
        case .current: .ready
        case .delayed: .caution
        case .divergent, .needsSnapshotVerification: .blocked
        }
    }
}

/// Sprint Q.6: identifiable wrapper that lets `.sheet(item:)` present
/// the `AutonomousLoopReportDetailView` keyed on the persisted record
/// identifier. The SwiftData `@Model` class is not `Identifiable` on
/// its own — wrapping it here keeps the model file untouched.
private struct PresentedLoopReport: Identifiable {
    let report: AutonomousLoopReportRecord

    var id: String { report.identifier }
}

private struct ActiveAutonomyRun: Identifiable {
    let taskID: String
    let taskTitle: String
    let plan: RunPlan

    var id: String { taskID }
}

private struct AutonomyMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ReadinessCheckRow: View {
    let check: AutonomyReadinessCheck

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(check.title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.12), in: Capsule())
                }
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private var label: String {
        switch check.state {
        case .ready: "Ready"
        case .caution: "Review"
        case .blocked: "Hold"
        }
    }

    private var color: Color {
        switch check.state {
        case .ready: .green
        case .caution: .orange
        case .blocked: .red
        }
    }
}

private struct StoredAutonomyTaskRow: View {
    let task: AutonomyTaskRecord
    let goalTitle: String?
    let providerName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    if let goalTitle {
                        Text(goalTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }
            HStack(spacing: 10) {
                Label(modeLabel, systemImage: "point.3.connected.trianglepath.dotted")
                if let providerName {
                    Label(providerName, systemImage: "externaldrive.connected.to.line.below")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private var modeLabel: String {
        AgentExecutionMode(rawValue: task.mode)?.label ?? task.mode
    }

    private var statusLabel: String {
        CoordinationStatus(rawValue: task.status)?.rawValue.capitalized ?? task.status.capitalized
    }

    private var statusColor: Color {
        switch CoordinationStatus(rawValue: task.status) {
        case .completed, .checkpointed:
            return .green
        case .blocked, .conflict:
            return .red
        case .cancelled:
            return .secondary
        case .inProgress:
            return .blue
        case .planned, .claimed, .none:
            return .orange
        }
    }
}

/// Sprint Q.5: renders a single `AutonomousLoopReportRecord` with a
/// halt-reason chip and a compact iteration timeline.
private struct AutonomyLoopReportRow: View {
    let report: AutonomousLoopReportRecord

    private var iterations: [AutonomousLoopIteration] {
        AutonomousLoopPersistence.decodeIterations(report.iterationsJSON)
    }

    private var chipTint: Color {
        switch report.haltReasonKind {
        case "completed": .green
        case "approvalRequired", "approvalCap": .blue
        case "denied", "validationFailureCap", "dependencyDeadlock": .red
        case "iterationCap": .orange
        default: .secondary
        }
    }

    private var chipLabel: String {
        switch report.haltReasonKind {
        case "completed": "Completed"
        case "approvalRequired": "Approval"
        case "denied": "Denied"
        case "validationFailureCap": "Validation"
        case "iterationCap": "Iteration cap"
        case "approvalCap": "Approval cap"
        case "dependencyDeadlock": "Dependency"
        default: report.haltReasonKind.capitalized
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Plan \(report.planID.prefix(8))")
                    .font(.subheadline.weight(.semibold))
                    .monospaced()
                Spacer()
                Text(chipLabel)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(chipTint.opacity(0.16), in: Capsule())
                    .overlay(Capsule().stroke(chipTint.opacity(0.55), lineWidth: 1))
                    .foregroundStyle(chipTint)
                    .accessibilityIdentifier("Autonomy.LoopHistory.Chip.\(report.identifier)")
            }
            Text(report.haltReasonLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 12) {
                Label("\(iterations.count) iter", systemImage: "list.number")
                Label("\(report.validationFailureCount) fail", systemImage: "xmark.octagon")
                    .foregroundStyle(report.validationFailureCount > 0 ? .red : .secondary)
                Label("\(report.approvalSurfaceCount) approval", systemImage: "checkmark.shield")
                    .foregroundStyle(report.approvalSurfaceCount > 0 ? .blue : .secondary)
                Spacer()
                Text(report.endedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if !iterations.isEmpty {
                HStack(spacing: 4) {
                    ForEach(iterations.prefix(12)) { iteration in
                        Circle()
                            .fill(iterationTint(for: iteration.status))
                            .frame(width: 8, height: 8)
                            .help("\(iteration.taskTitle): \(iteration.detail)")
                    }
                    if iterations.count > 12 {
                        Text("+\(iterations.count - 12)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("Autonomy.LoopHistory.Report.\(report.identifier)")
    }

    private func iterationTint(for status: AutonomousLoopIteration.Status) -> Color {
        switch status {
        case .completedAdvisory: .teal
        case .validationPassed: .green
        case .validationFailed: .red
        case .approvalRequired: .blue
        case .denied: .red
        case .dependenciesUnresolved: .orange
        }
    }
}
