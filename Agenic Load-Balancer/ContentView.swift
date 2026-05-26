//
//  ContentView.swift
//  Agenic Load-Balancer
//
//  Created by Zinco Verde on 5/5/26.
//

import AppKit
import Charts
import Combine
import CoreData
import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [AgentProject]
    @Query private var providers: [AgentProviderProfile]
    @Query private var usageEntries: [UsageLedgerEntry]
    @Query private var outcomes: [RunOutcomeRecord]
    @Query private var decisions: [RoutingDecisionRecord]
    @Query private var coordinationEvents: [CoordinationEventRecord]
    @Query private var snapshots: [CloudSnapshotRecord]
    @Query private var autonomyGoals: [AutonomyGoalRecord]
    @Query private var autonomyTasks: [AutonomyTaskRecord]
    @Query(sort: \AutonomyOperationRecord.createdAt, order: .reverse) private var autonomyOperations: [AutonomyOperationRecord]
    @Query(sort: \ConflictResolutionRecord.createdAt, order: .reverse) private var conflicts: [ConflictResolutionRecord]
    @Query(sort: \MachinePeerRecord.updatedAt, order: .reverse) private var machinePeers: [MachinePeerRecord]

    @State private var selectedSection: ConsoleSection? = .dashboard
    @State private var showingCommandBar = false
    @State private var showingSettingsSheet = false
    @State private var settingsInitialTab: AgenicSettingsTab = .storage
    @State private var promptRunSessions: [PromptRunSession] = []
    @State private var expandedProjectIDs: Set<String> = []
    @State private var cloudStatus = CloudSyncStatusSnapshot(
        containerIdentifier: AgenicDataModel.cloudKitContainerIdentifier,
        lastLocalSave: nil,
        lastCloudEvent: nil,
        status: "loading",
        detail: "Checking local repository."
    )

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Operate") {
                    sidebarItem(.dashboard, "Dashboard", "chart.xyaxis.line")
                    sidebarItem(.promptRouter, "Prompt Router", "point.3.connected.trianglepath.dotted")
                    sidebarItem(.autonomy, "Autonomy", "cpu")
                    sidebarItem(.history, "History", "clock.arrow.circlepath")
                }

                Section("Configure") {
                    sidebarItem(.providers, "Providers", "externaldrive.connected.to.line.below")
                    workspaceSidebar
                    sidebarItem(.conflictCenter, "Conflicts", "exclamationmark.triangle")
                    sidebarItem(.restoreCenter, "Restore", "icloud.and.arrow.down")
                    sidebarItem(.agentNotes, "AgentNotes", "checklist")
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detailView
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 640)
                .background(AgenicTheme.detailBackground)
        }
        .task {
            AppBootstrapper.ensureSeedData(in: modelContext)
            await refreshCloudStatus()
            await observeRemoteCloudChanges()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingCommandBar = true
                } label: {
                    Label("Command Bar", systemImage: "command")
                }
                .accessibilityIdentifier("Toolbar.CommandBar")

                Button {
                    selectedSection = .promptRouter
                } label: {
                    Label("New Prompt", systemImage: "plus.message")
                }
                .accessibilityIdentifier("Toolbar.NewPrompt")

                Button {
                    Task {
                        await refreshCloudStatus()
                        settingsInitialTab = .storage
                        showingSettingsSheet = true
                    }
                } label: {
                    Label("iCloud Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                }
                .accessibilityIdentifier("Toolbar.iCloudSync")

                Button {
                    settingsInitialTab = .generation
                    showingSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("Toolbar.Settings")
            }
        }
        .sheet(isPresented: $showingCommandBar) {
            CommandBarView(
                projects: projects,
                providers: providers,
                usageEntries: usageEntries,
                outcomes: outcomes,
                coordinationEvents: coordinationEvents
            )
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsView(initialTab: settingsInitialTab)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection ?? .dashboard {
        case .dashboard:
            DashboardView(
                providers: providers,
                usageEntries: usageEntries,
                outcomes: outcomes,
                cloudStatus: cloudStatus
            )
            .accessibilityIdentifier("Screen.Dashboard")
        case .promptRouter:
            PromptRouterView(
                projects: projects,
                providers: providers,
                usageEntries: usageEntries,
                outcomes: outcomes,
                coordinationEvents: coordinationEvents,
                runSessions: $promptRunSessions
            )
            .accessibilityIdentifier("Screen.PromptRouter")
        case .autonomy:
            AutonomyControlCenterView(
                projects: projects,
                providers: providers,
                usageEntries: usageEntries,
                outcomes: outcomes,
                coordinationEvents: coordinationEvents,
                snapshots: snapshots,
                draftPlan: { request in
                    try await AppServices.autonomyManager.draftPlan(request: request)
                }
            )
            .accessibilityIdentifier("Screen.Autonomy")
        case .providers:
            ProviderSetupView(providers: providers)
                .accessibilityIdentifier("Screen.Providers")
        case .projects:
            ProjectsView(projects: projects, coordinationEvents: coordinationEvents)
                .accessibilityIdentifier("Screen.Projects")
        case .workspace(let projectID):
            if let project = projects.first(where: { $0.identifier == projectID }) {
                WorkspaceProjectDetailView(
                    project: project,
                    tasks: taskSummaries(for: project),
                    onOpenProjects: { selectedSection = .projects }
                )
            } else {
                ProjectsView(projects: projects, coordinationEvents: coordinationEvents)
                    .accessibilityIdentifier("Screen.Projects")
            }
        case .workspaceTask(let taskID):
            if let summary = taskSummary(withID: taskID) {
                WorkspaceTaskDetailView(summary: summary)
            } else {
                ProjectsView(projects: projects, coordinationEvents: coordinationEvents)
                    .accessibilityIdentifier("Screen.Projects")
            }
        case .conflictCenter:
            ConflictCenterView(
                conflicts: conflicts,
                operations: autonomyOperations,
                peers: machinePeers,
                snapshots: snapshots,
                projects: projects,
                tasks: autonomyTasks
            )
            .accessibilityIdentifier("Screen.Conflicts")
        case .history:
            HistoryView(decisions: decisions, outcomes: outcomes, usageEntries: usageEntries)
                .accessibilityIdentifier("Screen.History")
        case .restoreCenter:
            RestoreCenterView(
                projects: projects,
                providers: providers,
                outcomes: outcomes,
                coordinationEvents: coordinationEvents,
                snapshots: snapshots,
                cloudStatus: cloudStatus
            )
            .accessibilityIdentifier("Screen.Restore")
        case .agentNotes:
            AgentNotesView(projects: projects, coordinationEvents: coordinationEvents)
                .accessibilityIdentifier("Screen.AgentNotes")
        }
    }

    private func sidebarItem(_ section: ConsoleSection, _ label: String, _ systemImage: String) -> some View {
        NavigationLink(value: section) {
            Label(label, systemImage: systemImage)
        }
        .accessibilityIdentifier("Sidebar.\(section.id)")
    }

    @ViewBuilder
    private var workspaceSidebar: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { !expandedProjectIDs.isEmpty || selectedSection?.isProjectRelated == true },
                set: { isExpanded in
                    if isExpanded {
                        expandedProjectIDs = Set(projects.map(\.identifier))
                    } else {
                        expandedProjectIDs.removeAll()
                    }
                }
            )
        ) {
            NavigationLink(value: ConsoleSection.projects) {
                Label("Manage Workspaces", systemImage: "folder.badge.gearshape")
            }
            .accessibilityIdentifier("Sidebar.ManageWorkspaces")

            ForEach(projects, id: \.identifier) { project in
                workspaceTree(project)
            }
        } label: {
            Label("Projects", systemImage: "folder.badge.gearshape")
                .accessibilityIdentifier("Sidebar.ProjectsDisclosure")
        }
    }

    @ViewBuilder
    private func workspaceTree(_ project: AgentProject) -> some View {
        let tasks = taskSummaries(for: project)
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedProjectIDs.contains(project.identifier) },
                set: { isExpanded in
                    if isExpanded {
                        expandedProjectIDs.insert(project.identifier)
                    } else {
                        expandedProjectIDs.remove(project.identifier)
                    }
                }
            )
        ) {
            NavigationLink(value: ConsoleSection.workspace(project.identifier)) {
                HStack {
                    Text("Workspace")
                    Spacer()
                    Text("\(tasks.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("Sidebar.WorkspaceRoot.\(project.identifier)")

            ForEach(tasks.prefix(6)) { task in
                NavigationLink(value: ConsoleSection.workspaceTask(task.id)) {
                    WorkspaceTaskSidebarRow(summary: task)
                }
                .accessibilityIdentifier("Sidebar.Task.\(task.id)")
            }

            if tasks.count > 6 {
                NavigationLink(value: ConsoleSection.workspace(project.identifier)) {
                    Text("Show \(tasks.count - 6) more")
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                Text(project.name)
                    .lineLimit(1)
                    .accessibilityIdentifier("Sidebar.Workspace.\(project.identifier)")
                Spacer()
                activeTaskIndicator(tasks)
            }
        }
    }

    @ViewBuilder
    private func activeTaskIndicator(_ tasks: [WorkspaceTaskSummary]) -> some View {
        if tasks.contains(where: \.isActive) {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 18, height: 18)
        } else if !tasks.isEmpty {
            Text("\(tasks.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func taskSummaries(for project: AgentProject) -> [WorkspaceTaskSummary] {
        let eventTasks = coordinationEvents
            .filter { $0.projectID == project.identifier }
            .map { event in
                WorkspaceTaskSummary(
                    id: "coordination:\(event.identifier)",
                    projectID: project.identifier,
                    projectName: project.name,
                    title: event.title,
                    subtitle: "\(event.phase) / \(event.wave) / \(event.step)",
                    detail: event.detail,
                    status: event.status,
                    providerID: nil,
                    runID: event.relatedRunID,
                    createdAt: event.createdAt,
                    updatedAt: event.createdAt,
                    source: "AgentNotes coordination"
                )
            }

        let eventRunIDs = Set(coordinationEvents.compactMap(\.relatedRunID))
        let runTasks = outcomes
            .filter { $0.projectID == project.identifier && !eventRunIDs.contains($0.runID) }
            .map { outcome in
                WorkspaceTaskSummary(
                    id: "run:\(outcome.runID)",
                    projectID: project.identifier,
                    projectName: project.name,
                    title: "Run \(outcome.runID.prefix(8))",
                    subtitle: outcome.providerID,
                    detail: outcome.userFeedback.isEmpty ? outcome.buildResult : outcome.userFeedback,
                    status: outcome.status,
                    providerID: outcome.providerID,
                    runID: outcome.runID,
                    createdAt: outcome.startedAt,
                    updatedAt: outcome.endedAt ?? outcome.startedAt,
                    source: "Run history"
                )
            }

        let goalIDs = Set(autonomyGoals.filter { $0.projectID == project.identifier }.map(\.identifier))
        let autonomyTaskSummaries = autonomyTasks
            .filter { task in task.goalID.map { goalIDs.contains($0) } ?? false }
            .map { task in
                WorkspaceTaskSummary(
                    id: "autonomy:\(task.identifier)",
                    projectID: project.identifier,
                    projectName: project.name,
                    title: task.title,
                    subtitle: AgentExecutionMode(rawValue: task.mode)?.label ?? task.mode,
                    detail: task.detail,
                    status: task.status,
                    providerID: task.assignedProviderID,
                    runID: nil,
                    createdAt: task.createdAt,
                    updatedAt: task.updatedAt,
                    source: "Autonomy task"
                )
            }

        return (eventTasks + runTasks + autonomyTaskSummaries)
            .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
    }

    private func taskSummary(withID id: String) -> WorkspaceTaskSummary? {
        projects.lazy
            .flatMap { taskSummaries(for: $0) }
            .first { $0.id == id }
    }

    private func refreshCloudStatus() async {
        let status = await AppServices.cloudSync.currentStatus()
        await MainActor.run {
            cloudStatus = status
        }
    }

    /// Listen for `NSPersistentStoreRemoteChange` notifications for the
    /// duration of the view's lifetime. SwiftData wraps
    /// `NSPersistentCloudKitContainer`, which posts this notification each
    /// time iCloud delivers a remote change. The loop terminates when the
    /// surrounding `.task` is cancelled (view disappears).
    private func observeRemoteCloudChanges() async {
        let stream = NotificationCenter.default.notifications(
            named: .NSPersistentStoreRemoteChange
        )
        for await _ in stream {
            await AppServices.cloudSync.recordRemoteNotification()
            await refreshCloudStatus()
        }
    }
}

private enum ConsoleSection: Identifiable, Hashable {
    case dashboard
    case promptRouter
    case autonomy
    case providers
    case projects
    case workspace(String)
    case workspaceTask(String)
    case conflictCenter
    case history
    case restoreCenter
    case agentNotes

    var id: String {
        switch self {
        case .dashboard: "dashboard"
        case .promptRouter: "promptRouter"
        case .autonomy: "autonomy"
        case .providers: "providers"
        case .projects: "projects"
        case .workspace(let projectID): "workspace:\(projectID)"
        case .workspaceTask(let taskID): "workspaceTask:\(taskID)"
        case .conflictCenter: "conflictCenter"
        case .history: "history"
        case .restoreCenter: "restoreCenter"
        case .agentNotes: "agentNotes"
        }
    }

    var isProjectRelated: Bool {
        switch self {
        case .projects, .workspace, .workspaceTask:
            return true
        default:
            return false
        }
    }
}

private struct WorkspaceTaskSummary: Identifiable, Hashable {
    let id: String
    let projectID: String
    let projectName: String
    let title: String
    let subtitle: String
    let detail: String
    let status: String
    let providerID: String?
    let runID: String?
    let createdAt: Date
    let updatedAt: Date
    let source: String

    var isActive: Bool {
        CoordinationStatus.isActiveForPreflight(status) || status == RunStatus.running.rawValue
    }

    var statusTint: Color {
        switch status {
        case RunStatus.succeeded.rawValue, CoordinationStatus.completed.rawValue, CoordinationStatus.checkpointed.rawValue:
            return .green
        case RunStatus.failed.rawValue, CoordinationStatus.conflict.rawValue, CoordinationStatus.blocked.rawValue:
            return .red
        case RunStatus.cancelled.rawValue, CoordinationStatus.cancelled.rawValue:
            return .orange
        case RunStatus.running.rawValue, CoordinationStatus.inProgress.rawValue:
            return .blue
        default:
            return .secondary
        }
    }
}

private struct WorkspaceTaskSidebarRow: View {
    let summary: WorkspaceTaskSummary

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(summary.statusTint)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .lineLimit(1)
                Text(summary.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if summary.isActive {
                ProgressView()
                    .scaleEffect(0.45)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.leading, 14)
    }
}

private struct WorkspaceProjectDetailView: View {
    let project: AgentProject
    let tasks: [WorkspaceTaskSummary]
    let onOpenProjects: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.largeTitle.weight(.semibold))
                        Text(project.rootPath ?? "No folder selected")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        onOpenProjects()
                    } label: {
                        Label("Workspace Settings", systemImage: "slider.horizontal.3")
                    }
                }

                GlassPanel {
                    HStack(spacing: 16) {
                        WorkspaceMetric(label: "Tasks", value: "\(tasks.count)")
                        WorkspaceMetric(label: "Active", value: "\(tasks.filter(\.isActive).count)")
                        WorkspaceMetric(label: "Runs", value: "\(tasks.filter { $0.runID != nil }.count)")
                        WorkspaceMetric(label: "Tool policy", value: project.allowToolCalling ? "Allowed" : "Off")
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Workspace Paths")
                            .font(.headline)
                        LabeledContent("Working path", value: project.defaultWorkingPath ?? project.rootPath ?? "Provider default")
                        LabeledContent("Temporary path", value: project.temporaryWorkingPath ?? "Provider default")
                        LabeledContent("Context compaction", value: project.contextCompactionEnabled ? "\(project.contextCompactionThresholdTokens.formatted()) tokens" : "Disabled")
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tasks")
                            .font(.headline)
                        if tasks.isEmpty {
                            ContentUnavailableView(
                                "No tasks tracked yet",
                                systemImage: "checklist",
                                description: Text("Runs, AgentNotes coordination records, and autonomy tasks for this workspace appear here.")
                            )
                        } else {
                            ForEach(tasks) { task in
                                WorkspaceTaskInlineRow(summary: task)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .overlay(alignment: .topLeading) {
            accessibilityMarker("Screen.Workspace.\(project.identifier)")
        }
    }

    private func accessibilityMarker(_ identifier: String) -> some View {
        Text(identifier)
            .font(.caption2)
            .opacity(0.01)
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(identifier)
    }
}

private struct WorkspaceTaskDetailView: View {
    let summary: WorkspaceTaskSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.title)
                        .font(.largeTitle.weight(.semibold))
                    Text("\(summary.projectName) · \(summary.source)")
                        .foregroundStyle(.secondary)
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Status") {
                            Text(summary.status)
                                .foregroundStyle(summary.statusTint)
                        }
                        LabeledContent("Updated", value: summary.updatedAt.formatted(date: .abbreviated, time: .standard))
                        LabeledContent("Created", value: summary.createdAt.formatted(date: .abbreviated, time: .standard))
                        if let providerID = summary.providerID {
                            LabeledContent("Provider", value: providerID)
                        }
                        if let runID = summary.runID {
                            LabeledContent("Run ID", value: runID)
                        }
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary.subtitle)
                            .font(.headline)
                        Text(summary.detail.isEmpty ? "No detail recorded." : summary.detail)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(24)
        }
        .overlay(alignment: .topLeading) {
            accessibilityMarker("Screen.WorkspaceTask.\(summary.id)")
        }
    }

    private func accessibilityMarker(_ identifier: String) -> some View {
        Text(identifier)
            .font(.caption2)
            .opacity(0.01)
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(identifier)
    }
}

private struct WorkspaceMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceTaskInlineRow: View {
    let summary: WorkspaceTaskSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(summary.statusTint)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.subheadline.weight(.medium))
                Text(summary.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summary.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(summary.status)
                .font(.caption)
                .foregroundStyle(summary.statusTint)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }
}

@MainActor
@Observable
final class PromptRunSession: Identifiable {
    let id: UUID
    let plan: RunPlan
    let dispatcher: RunDispatcher
    let createdAt: Date

    init(
        id: UUID = UUID(),
        plan: RunPlan,
        dispatcher: RunDispatcher = RunDispatcher(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.plan = plan
        self.dispatcher = dispatcher
        self.createdAt = createdAt
    }
}

enum AgenicTheme {
    static let cornerRadius: CGFloat = 8

    static var detailBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.teal.opacity(0.035),
                Color.indigo.opacity(0.03),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glassTint: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.07),
                Color.teal.opacity(0.045),
                Color.indigo.opacity(0.035),
                Color.black.opacity(0.035),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var settingsSidebarTint: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.08),
                Color.gray.opacity(0.12),
                Color.teal.opacity(0.04),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func accentColor(for key: String) -> Color {
        switch key {
        case _ where key.localizedCaseInsensitiveContains("cloud"): return .teal
        case _ where key.localizedCaseInsensitiveContains("cost"): return .green
        case _ where key.localizedCaseInsensitiveContains("run"): return .orange
        case _ where key.localizedCaseInsensitiveContains("provider"): return .blue
        case _ where key.localizedCaseInsensitiveContains("accuracy"): return .cyan
        case _ where key.localizedCaseInsensitiveContains("latency"): return .purple
        case _ where key.localizedCaseInsensitiveContains("success"): return .green
        case _ where key.localizedCaseInsensitiveContains("limit"): return .mint
        default: return .accentColor
        }
    }

    static func metricGradient(for color: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                color.opacity(0.34),
                color.opacity(0.16),
                Color.white.opacity(0.045),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct DashboardView: View {
    let providers: [AgentProviderProfile]
    let usageEntries: [UsageLedgerEntry]
    let outcomes: [RunOutcomeRecord]
    let cloudStatus: CloudSyncStatusSnapshot

    private var configuredProviders: [AgentProviderProfile] {
        providers.filter(\.isConfiguredForDashboard)
    }

    private var usage: [UsageSnapshot] {
        UsageSnapshotBuilder.build(
            from: usageEntries,
            outcomes: outcomes,
            providers: configuredProviders
        )
    }

    private var accuracy: [AccuracySnapshot] {
        AccuracySnapshotBuilder.build(from: outcomes, providers: configuredProviders)
    }

    private var reliability: [ProviderReliabilitySnapshot] {
        ProviderReliabilityBuilder.build(providers: configuredProviders, outcomes: outcomes)
    }

    private var heatmapCells: [DashboardHeatmapCell] {
        DashboardMetricFactory.heatmapCells(
            providers: configuredProviders,
            usage: usage,
            accuracy: accuracy,
            reliability: reliability
        )
    }

    private var performanceSummaries: [ProviderPerformanceSummary] {
        PerformanceHistoryBuilder.build(
            providers: configuredProviders,
            outcomes: outcomes,
            usageEntries: usageEntries
        )
        .filter { $0.totalRuns > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
                    KPIBlock(title: "Providers", value: "\(configuredProviders.count)", detail: "\(availableProviderCount) locally available")
                    KPIBlock(title: "Runs", value: "\(outcomes.count)", detail: "\(ratedRunCount) rated for accuracy")
                    KPIBlock(title: "Estimated Cost", value: totalCost.formatted(.currency(code: "USD")), detail: "Observed today")
                    KPIBlock(title: "CloudKit", value: cloudStatus.status.capitalized, detail: cloudStatus.containerIdentifier)
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Model Use Heatmap")
                            .font(.headline)
                        Text("Configured providers only — availability, limit headroom, accuracy, latency, success rate, and observed cost — computed from SwiftData and syncable through private CloudKit metadata.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if heatmapCells.isEmpty {
                            ContentUnavailableView(
                                "No configured providers",
                                systemImage: "externaldrive.badge.checkmark",
                                description: Text("Configure or successfully probe a provider before it appears in the heatmap.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                                ForEach(heatmapCells) { cell in
                                    HeatmapCell(cell: cell)
                                }
                            }
                        }
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Limits & Quotas")
                            .font(.headline)
                        Text("Quota usage today against the configured `UsageLimitPolicy` (defaults seeded per provider family; user overrides land in Phase 5).")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(usage) { snapshot in
                            QuotaRow(
                                providerName: configuredProviders.first { $0.identifier == snapshot.providerID }?.displayName ?? snapshot.providerID,
                                snapshot: snapshot
                            )
                        }
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Provider Accuracy")
                            .font(.headline)
                        ForEach(accuracy) { snapshot in
                            let providerName = configuredProviders.first { $0.identifier == snapshot.providerID }?.displayName ?? snapshot.providerID
                            HStack {
                                Text(providerName)
                                    .frame(width: 180, alignment: .leading)
                                ProgressView(value: snapshot.averageScore)
                                Text(snapshot.averageScore.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 54, alignment: .trailing)
                                Text("\(snapshot.totalRatedRuns) rated")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 72, alignment: .trailing)
                            }
                        }
                    }
                }

                if !performanceSummaries.isEmpty {
                    PerformanceTrendPanel(summaries: performanceSummaries)
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agenic Load-Balancer")
                .font(.largeTitle.weight(.semibold))
            Text("Mac orchestration console for local coding agents, provider limits, model accuracy, and cross-agent coordination.")
                .foregroundStyle(.secondary)
        }
    }

    private var availableProviderCount: Int {
        configuredProviders.filter { $0.installedState == ProviderAvailabilityState.available.rawValue }.count
    }

    private var ratedRunCount: Int {
        outcomes.filter { $0.accuracyRating != AccuracyRating.unrated.rawValue }.count
    }

    private var totalCost: Double {
        usage.reduce(0) { $0 + $1.estimatedCostToday }
    }
}

private struct PromptRouterView: View {
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
    @Binding var runSessions: [PromptRunSession]

    @State private var prompt = ""
    @State private var selectedProjectID: String?
    @State private var selectedMode: AgentExecutionMode = .implementation
    @State private var recommendation = RoutingRecommendation()
    @State private var selectedScoreID: UUID?
    @State private var commandPreview = "Rank agents to preview the approved command."
    @State private var approvalStatus = ""
    @State private var presentedRunSession: PromptRunSession?

    private var rankableProviders: [AgentProviderProfile] {
        providers.filter(\.isConfiguredForDashboard)
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < 1_040 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        promptColumn
                        routingColumn
                    }
                    .padding(24)
                }
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        promptColumn
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)

                    Divider()

                    ScrollView {
                        routingColumn
                            .padding(20)
                    }
                    .frame(width: min(max(proxy.size.width * 0.36, 360), 520))
                }
            }
        }
        .sheet(item: $presentedRunSession) { session in
            ApprovalSheetView(
                plan: session.plan,
                dispatcher: session.dispatcher,
                onClose: {
                    close(session: session)
                }
            )
        }
    }

    @ViewBuilder
    private var promptColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Prompt Router")
                .font(.largeTitle.weight(.semibold))

            GlassPanel {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            projectPicker
                            modePicker
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            projectPicker
                            modePicker
                        }
                    }

                    TextEditor(text: $prompt)
                        .font(.body.monospaced())
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.separator.opacity(0.35), lineWidth: 1)
                        )

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            actionButtons
                            statusText
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            actionButtons
                            statusText
                        }
                    }
                }
            }

            liveRunDock

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Approved Command Preview")
                        .font(.headline)
                    Text(commandPreview)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var projectPicker: some View {
        Picker("Project", selection: $selectedProjectID) {
            Text("No Project").tag(String?.none)
            ForEach(projects, id: \.identifier) { project in
                Text(project.name).tag(Optional(project.identifier))
            }
        }
        .frame(maxWidth: 360)
    }

    private var modePicker: some View {
        Picker("Mode", selection: $selectedMode) {
            ForEach(AgentExecutionMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .frame(maxWidth: 260)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                rankRoutes()
            } label: {
                Label("Rank Agents", systemImage: "list.bullet.rectangle.portrait")
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                presentApprovalSheet()
            } label: {
                Label("Review & Run…", systemImage: "checkmark.seal")
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(selectedScore == nil)
        }
    }

    private var statusText: some View {
        Text(approvalStatus)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var liveRunDock: some View {
        if !runSessions.isEmpty {
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Live Runs")
                        .font(.headline)
                    ForEach(runSessions) { session in
                        PromptRunDockRow(
                            session: session,
                            onShow: { presentedRunSession = session },
                            onCancel: { session.dispatcher.cancel() },
                            onClear: { clear(session: session) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var routingColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Routing Rationale")
                .font(.title2.weight(.semibold))

            if recommendation.ranked.isEmpty {
                ContentUnavailableView(
                    "No routes ranked",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Enter a prompt and rank agents to see score breakdowns.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ForEach(recommendation.ranked) { score in
                    RouteScoreRow(
                        score: score,
                        tieBreak: recommendation.tieBreak,
                        isSelected: selectedScoreID == score.id
                    ) {
                        selectedScoreID = score.id
                        buildCommandPreview(for: score)
                    }
                }
            }
        }
    }

    private var selectedProject: AgentProject? {
        projects.first { $0.identifier == selectedProjectID }
    }

    private var selectedScore: RoutingScoreBreakdown? {
        recommendation.ranked.first { $0.id == selectedScoreID }
    }

    private func rankRoutes() {
        let routeProviders = rankableProviders
        let providerSnapshots = routeProviders.map { $0.snapshot() }
        let usage = UsageSnapshotBuilder.build(
            from: usageEntries,
            outcomes: outcomes,
            providers: routeProviders
        )
        let accuracy = AccuracySnapshotBuilder.build(from: outcomes, providers: routeProviders)
        let reliability = ProviderReliabilityBuilder.build(providers: routeProviders, outcomes: outcomes)
        let coordination = coordinationEvents.map { $0.snapshot() }
        let promptText = prompt
        let mode = selectedMode

        Task {
            let nextRecommendation = await AppServices.routingRecommendation.recommend(
                prompt: promptText,
                mode: mode,
                providers: providerSnapshots,
                usage: usage,
                accuracy: accuracy,
                reliability: reliability,
                coordinationEvents: coordination
            )
            await MainActor.run {
                recommendation = nextRecommendation
                selectedScoreID = nextRecommendation.selected?.id
                approvalStatus = nextRecommendation.selected.map { "Recommended \($0.providerName)." }
                    ?? "No configured provider available."
                if let selected = nextRecommendation.selected {
                    buildCommandPreview(for: selected)
                }
            }
        }
    }

    private func buildCommandPreview(for score: RoutingScoreBreakdown) {
        guard let provider = rankableProviders.first(where: { $0.identifier == score.providerID }) else {
            commandPreview = "Provider profile not found."
            return
        }

        do {
            let command = try AgentAdapterFactory
                .makeAdapter(providerID: score.providerID)
                .buildCommand(
                    prompt: prompt,
                    projectPath: effectiveWorkingPath,
                    mode: selectedMode,
                    provider: provider.snapshot()
                )
            commandPreview = command.displayCommand
        } catch {
            commandPreview = error.localizedDescription
        }
    }

    private func currentRunPlan() -> RunPlan? {
        guard let score = selectedScore,
              let provider = rankableProviders.first(where: { $0.identifier == score.providerID }) else {
            return nil
        }
        return RunPlan(
            providerSnapshot: provider.snapshot(),
            providerID: provider.identifier,
            providerName: provider.displayName,
            prompt: prompt,
            projectID: selectedProject?.identifier,
            projectName: selectedProject?.name,
            projectRootPath: selectedProject?.rootPath,
            defaultWorkingPath: effectiveWorkingPath,
            temporaryWorkingPath: effectiveTemporaryPath,
            mode: selectedMode,
            score: score,
            promptExcerptSyncEnabled: selectedProject?.promptExcerptSyncEnabled ?? false,
            allowToolCalling: selectedProject?.allowToolCalling ?? defaultAllowToolCalling,
            allowShellTools: selectedProject?.allowShellTools ?? defaultAllowShellTools,
            allowNetworkSearch: selectedProject?.allowNetworkSearch ?? defaultAllowNetworkSearch,
            allowFilesystemWrites: selectedProject?.allowFilesystemWrites ?? defaultAllowFilesystemWrites,
            contextCompactionEnabled: selectedProject?.contextCompactionEnabled ?? appContextCompactionEnabled,
            contextCompactionThresholdTokens: selectedProject?.contextCompactionThresholdTokens ?? appContextCompactionThresholdTokens
        )
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

    private func presentApprovalSheet() {
        guard let plan = currentRunPlan() else { return }
        let session = PromptRunSession(plan: plan)
        runSessions.insert(session, at: 0)
        presentedRunSession = session
        approvalStatus = "Prepared \(plan.providerName) run."
    }

    private func close(session: PromptRunSession) {
        presentedRunSession = nil
        approvalStatus = statusText(for: session.dispatcher)
        if session.dispatcher.status == .idle && session.dispatcher.activeRunID == nil {
            clear(session: session)
        }
    }

    private func clear(session: PromptRunSession) {
        if session.dispatcher.status == .running || session.dispatcher.status == .preparing {
            session.dispatcher.cancel()
        }
        runSessions.removeAll { $0.id == session.id }
    }

    private func statusText(for dispatcher: RunDispatcher) -> String {
        switch dispatcher.status {
        case .idle: return ""
        case .preparing: return "Preparing dispatch…"
        case .running: return "Run is still in progress."
        case .succeeded: return "Last run succeeded."
        case .failed: return "Last run failed: \(dispatcher.lastError ?? "see console")."
        case .cancelled: return "Last run was cancelled."
        }
    }
}

struct ApprovalSheetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let plan: RunPlan
    let dispatcher: RunDispatcher
    let allowsConsoleHide: Bool
    let onClose: () -> Void

    @State private var elapsedSeconds: Double = 0
    @State private var preflightExcerpt: String?
    @State private var preflightLoaded: Bool = false
    @State private var preflightSummary: AgentNotesPreflightSummary?
    @State private var preflightStatusText: String?

    init(
        plan: RunPlan,
        dispatcher: RunDispatcher,
        allowsConsoleHide: Bool = true,
        onClose: @escaping () -> Void
    ) {
        self.plan = plan
        self.dispatcher = dispatcher
        self.allowsConsoleHide = allowsConsoleHide
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if dispatcher.status == .idle {
                        agentNotesPreflightPanel
                        contextBudgetPanel
                        approvalSummary
                    } else {
                        runStatusBanner
                        continuationPanel
                        if plan.mode == .commitPushCheckpoint || dispatcher.checkpointStatus != .notRequested {
                            checkpointBanner
                        }
                        liveConsole
                        if dispatcher.status.isTerminal {
                            outcomeRating
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 620, idealHeight: 720)
        .background(.regularMaterial)
        .interactiveDismissDisabled(!allowsConsoleHide && (dispatcher.status == .preparing || dispatcher.status == .running))
        .task {
            await loadPreflightExcerpt()
        }
        .onDisappear {
            onClose()
        }
        .onReceive(timerPublisher) { _ in
            if let started = dispatcher.startedAt {
                let end = dispatcher.endedAt ?? Date()
                elapsedSeconds = end.timeIntervalSince(started)
            } else {
                elapsedSeconds = 0
            }
        }
    }

    private func loadPreflightExcerpt() async {
        defer { preflightLoaded = true }
        guard let rootPath = plan.projectRootPath, !rootPath.isEmpty else {
            preflightExcerpt = nil
            preflightSummary = nil
            preflightStatusText = "No project root."
            return
        }
        guard let fullAgentNotes = await AppServices.coordination.readAgentNotes(rootPath: rootPath) else {
            preflightExcerpt = nil
            preflightSummary = nil
            preflightStatusText = nil
            return
        }
        let activeAgentNotes = AgentNotesPreflightFilter.activeCoordinationText(from: fullAgentNotes)
        preflightExcerpt = Self.previewExcerpt(from: activeAgentNotes)

        let intelligence = AgentNotesIntelligenceFactory.makeDefault()
        do {
            preflightSummary = try await intelligence.summarizePreflight(
                agentNotes: activeAgentNotes,
                prompt: plan.prompt,
                mode: plan.mode
            )
            preflightStatusText = "Intelligent summary ready"
        } catch AgentNotesIntelligenceError.unavailable(let reason) {
            preflightSummary = nil
            preflightStatusText = reason
        } catch {
            preflightSummary = nil
            preflightStatusText = error.localizedDescription
        }
    }

    private static func previewExcerpt(from text: String, maxBytes: Int = 4_000) -> String {
        guard text.count > maxBytes else { return text }
        return String(text.prefix(maxBytes)) + "\n…[truncated for preview]"
    }

    @ViewBuilder
    private var agentNotesPreflightPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Preflight · AgentNotes")
                        .font(.headline)
                    Spacer()
                    if preflightLoaded {
                        Text(preflightHeaderStatus)
                            .font(.caption)
                            .foregroundStyle(preflightHeaderColor)
                    } else {
                        Text("Loading…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let preflightStatusText, preflightSummary == nil, preflightExcerpt != nil {
                    Text(preflightStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let preflightSummary {
                    VStack(alignment: .leading, spacing: 8) {
                        if !preflightSummary.relevantActiveClaims.isEmpty {
                            Text("Relevant claims")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            ForEach(preflightSummary.relevantActiveClaims, id: \.self) { claim in
                                Label(claim, systemImage: "checklist")
                                    .font(.caption)
                            }
                        }
                        if !preflightSummary.blockingConflicts.isEmpty {
                            Text("Blocking conflicts")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            ForEach(preflightSummary.blockingConflicts, id: \.self) { conflict in
                                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        if !preflightSummary.suggestedClaim.isEmpty {
                            Label(preflightSummary.suggestedClaim, systemImage: "tag")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                        ScrollView {
                            Text(preflightSummary.promptInjectionText)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 120)
                        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                    }
                } else if let excerpt = preflightExcerpt, !excerpt.isEmpty {
                    ScrollView {
                        Text(excerpt)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 160)
                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                } else if preflightLoaded {
                    Label("No AgentNotes.md detected. Add a project workspace to enable cross-agent coordination.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
    }

    private var preflightHeaderStatus: String {
        if preflightSummary != nil { return "Summary ready" }
        if preflightExcerpt != nil { return "Using excerpt fallback" }
        return "No AgentNotes.md found"
    }

    private var preflightHeaderColor: Color {
        if preflightSummary != nil { return Color.green }
        if preflightExcerpt != nil { return Color.orange }
        return Color.orange
    }

    @ViewBuilder
    private var contextBudgetPanel: some View {
        let estimate = approvalTokenEstimate
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Context budget")
                        .font(.headline)
                    Spacer()
                    Text(estimate.risk.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(contextBudgetColor(estimate.risk))
                }
                Text(estimate.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    budgetMetric("Prompt", estimate.userPromptTokens)
                    budgetMetric("AgentNotes", estimate.agentNotesTokens)
                    budgetMetric("Policy", estimate.workspacePolicyTokens)
                    budgetMetric("Path", estimate.projectContextTokens)
                }
                if estimate.needsCompaction {
                    Label(
                        plan.contextCompactionEnabled
                            ? "Preflight context will be compacted before dispatch if it stays above the threshold."
                            : "Context compaction is disabled for this workspace.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(plan.contextCompactionEnabled ? Color.orange : Color.red)
                }
            }
        }
    }

    private func budgetMetric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var approvalTokenEstimate: TokenBudgetEstimate {
        TokenBudgetEstimator.estimatePreflight(
            userPrompt: plan.prompt,
            agentNotesExcerpt: preflightSummary?.promptInjectionText ?? preflightExcerpt,
            workspacePolicy: RunDispatcher.workspacePolicyPrompt(for: plan),
            projectRootPath: RunDispatcher.effectiveWorkingPath(for: plan),
            providerID: plan.providerID,
            contextCompactionEnabled: plan.contextCompactionEnabled,
            thresholdTokens: plan.contextCompactionThresholdTokens
        )
    }

    private func contextBudgetColor(_ risk: TokenBudgetRisk) -> Color {
        switch risk {
        case .low: Color.green
        case .elevated: Color.accentColor
        case .high: Color.orange
        case .overLimit: Color.red
        }
    }

    @ViewBuilder
    private var checkpointBanner: some View {
        GlassPanel {
            HStack(spacing: 10) {
                Image(systemName: checkpointIcon)
                    .foregroundStyle(checkpointColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Git checkpoint")
                        .font(.subheadline.weight(.medium))
                    Text(dispatcher.checkpointStatus.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if case .succeeded(let sha, _, _) = dispatcher.checkpointStatus {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sha, forType: .string)
                    } label: {
                        Label("Copy SHA", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var checkpointIcon: String {
        switch dispatcher.checkpointStatus {
        case .notRequested: "checkmark.circle"
        case .pending: "clock.arrow.circlepath"
        case .succeeded: "checkmark.seal.fill"
        case .nothingToCommit: "tray"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var checkpointColor: Color {
        switch dispatcher.checkpointStatus {
        case .notRequested: Color.secondary
        case .pending: Color.accentColor
        case .succeeded: Color.green
        case .nothingToCommit: Color.orange
        case .failed: Color.red
        }
    }

    private var timerPublisher: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.providerName)
                    .font(.title2.weight(.semibold))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(plan.mode.label)
                    .foregroundStyle(.secondary)
                Spacer()
                StatusPill(status: dispatcher.status)
            }
            Text(plan.projectName.map { "Project: \($0)" } ?? "No project selected (workspace-less run).")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var approvalSummary: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Score breakdown")
                    .font(.headline)
                ScoreBar(label: "Availability", value: plan.score.availabilityScore)
                ScoreBar(label: "Capability", value: plan.score.capabilityScore)
                ScoreBar(label: "Limit headroom", value: plan.score.limitScore)
                ScoreBar(label: "Accuracy", value: plan.score.accuracyScore)
                ScoreBar(label: "Reliability", value: plan.score.reliabilityScore)
                ScoreBar(label: "Speed", value: plan.score.speedScore)
                ScoreBar(label: "Cost", value: plan.score.costScore)
                Divider()
                Text(plan.score.rationale)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }

        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cost & limits")
                    .font(.headline)
                LabeledContent("Estimated cost", value: plan.score.estimatedCostUSD.formatted(.currency(code: "USD")))
                LabeledContent("Limit impact", value: plan.score.limitImpact)
                LabeledContent("Reliability", value: plan.score.reliabilityImpact)
                if !plan.score.coordinationWarning.isEmpty {
                    Label(plan.score.coordinationWarning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }

        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Command preview")
                    .font(.headline)
                Text(commandPreview)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                if let path = plan.projectRootPath {
                    LabeledContent("Working directory") {
                        Text(path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Text("Implementation, repair/debug, and commit/push checkpoints require explicit approval per AgentNotes coordination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var runStatusBanner: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(dispatcher.displayedCommand.isEmpty ? commandPreview : dispatcher.displayedCommand)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                    Text(elapsedString)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let exit = dispatcher.exitCode {
                    Text("Exit code: \(exit)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let error = dispatcher.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var continuationPanel: some View {
        if let continuation = dispatcher.continuationPlan {
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Continuation ready", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                        Spacer()
                        Text("\(continuation.estimatedResumeTokens.formatted()) est. tokens")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        let triggerLabel = ContinuationTriggerCategory(rawValue: continuation.triggerCategory)?.label
                            ?? continuation.triggerCategory
                        Text("Chain depth \(continuation.chainDepth)")
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.18), in: Capsule())
                        Text(triggerLabel)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.18), in: Capsule())
                        if continuation.requiresApproval {
                            Text("Approval-gated")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.yellow.opacity(0.22), in: Capsule())
                        } else {
                            Text("Auto-resume ready")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.22), in: Capsule())
                        }
                        if continuation.workspaceExcerptCount > 0 {
                            Text("\(continuation.workspaceExcerptCount) workspace excerpt(s)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.18), in: Capsule())
                        }
                    }
                    Text(continuation.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    ScrollView {
                        Text(continuation.prompt)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 150)
                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(continuation.prompt, forType: .string)
                    } label: {
                        Label("Copy continuation prompt", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var liveConsole: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Live console")
                    .font(.headline)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if dispatcher.logs.isEmpty {
                                Text("Awaiting output…")
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                            } else {
                                ForEach(dispatcher.logs) { line in
                                    LogLineView(line: line)
                                        .id(line.id)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .frame(minHeight: 220, maxHeight: 360)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: dispatcher.logs.count) { _, _ in
                        if let last = dispatcher.logs.last {
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Label("\(dispatcher.promptTokens) prompt tok", systemImage: "text.alignleft")
                    Label("\(dispatcher.completionTokens) completion tok", systemImage: "text.alignright")
                    if dispatcher.cachedPromptTokens > 0 {
                        Label("\(dispatcher.cachedPromptTokens) cached", systemImage: "bolt.horizontal.circle")
                    }
                    if dispatcher.reasoningTokens > 0 {
                        Label("\(dispatcher.reasoningTokens) reasoning", systemImage: "brain")
                    }
                    if dispatcher.preprocessingSeconds > 0 {
                        Label(dispatcher.preprocessingSeconds.formattedDurationSeconds, systemImage: "timer")
                    }
                    if let estimate = dispatcher.preflightTokenEstimate {
                        Label("\(estimate.totalInputTokens.formatted()) est input", systemImage: "gauge.with.dots.needle.50percent")
                    }
                    Spacer()
                    if let runID = dispatcher.activeRunID {
                        Text("Run \(runID.prefix(8))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var outcomeRating: some View {
        if dispatcher.status == .succeeded {
            aiSummaryPanel
        }
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rate outcome")
                    .font(.headline)
                Text("Accuracy ratings feed the routing engine and dashboard heatmap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(AccuracyRating.allCases) { rating in
                        AccuracyRatingButton(
                            rating: rating,
                            isAISuggested: rating == aiSuggestedRating,
                            action: {
                                dispatcher.rateOutcome(rating, in: modelContext)
                            }
                        )
                    }
                }
                if aiSuggestedRating != nil {
                    Label("Highlighted rating is the AI suggestion. Your manual selection always wins.", systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Phase 7.2: render the AI-generated outcome summary as a Liquid Glass
    /// card. Reflects the four states of `RunDispatcher.AISummaryStatus`
    /// (pending / succeeded / unavailable / failed) so the user always sees
    /// what happened, never a silent UI.
    @ViewBuilder
    private var aiSummaryPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "sparkles")
                        .symbolEffect(.breathe, isActive: dispatcher.aiSummaryStatus == .pending)
                        .foregroundStyle(Color.accentColor)
                    Text("Outcome summary")
                        .font(.headline)
                    Spacer()
                    Text(aiSummaryBadgeLabel)
                        .font(.caption)
                        .foregroundStyle(aiSummaryBadgeColor)
                }

                switch dispatcher.aiSummaryStatus {
                case .notRequested:
                    Text("Awaiting summary request…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .pending:
                    Text("Apple Foundation Models is reading the captured output…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .unavailable(let reason):
                    Label(reason, systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let reason):
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .succeeded(let summary):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary.oneLineDescription)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 16) {
                            if let passed = summary.testsPassed, let failed = summary.testsFailed {
                                Label("\(passed) passed", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Label("\(failed) failed", systemImage: "xmark.octagon.fill")
                                    .foregroundStyle(failed > 0 ? Color.red : Color.secondary)
                            }
                            Label("Suggested: \(summary.suggestedAccuracyRating.rawValue)", systemImage: "wand.and.stars")
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                        }
                        .font(.caption)

                        if !summary.filesChanged.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Files touched (\(summary.filesChanged.count))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                ForEach(summary.filesChanged.prefix(8), id: \.self) { path in
                                    Text(path)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if summary.filesChanged.count > 8 {
                                    Text("…and \(summary.filesChanged.count - 8) more")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Phase 7.2: read the suggested rating off the dispatcher status, or
    /// nil when the model hasn't returned (yet) / declined.
    private var aiSuggestedRating: AccuracyRating? {
        if case let .succeeded(summary) = dispatcher.aiSummaryStatus {
            return summary.suggestedAccuracyRating
        }
        return nil
    }

    /// Right-aligned status badge text shown in the AI summary card header.
    private var aiSummaryBadgeLabel: String {
        switch dispatcher.aiSummaryStatus {
        case .notRequested: return "Idle"
        case .pending: return "Generating"
        case .unavailable: return "Unavailable"
        case .failed: return "Error"
        case .succeeded: return "Ready"
        }
    }

    private var aiSummaryBadgeColor: Color {
        switch dispatcher.aiSummaryStatus {
        case .notRequested: return Color.secondary
        case .pending: return Color.accentColor
        case .unavailable: return Color.secondary
        case .failed: return Color.orange
        case .succeeded: return Color.green
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            switch dispatcher.status {
            case .idle:
                Spacer()
                Button("Cancel", role: .cancel) { dismissSheet() }
                Button {
                    dispatcher.dispatch(
                        plan: plan,
                        agentNotesExcerpt: preflightExcerpt,
                        agentNotesPreflightSummary: preflightSummary,
                        modelContext: modelContext
                    )
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
            case .preparing, .running:
                Button {
                    dispatcher.cancel()
                } label: {
                    Label("Cancel run", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                Spacer()
                Text(allowsConsoleHide ? "Run continues if you hide this console." : "Run in progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if allowsConsoleHide {
                    Button("Hide Console") { dismissSheet() }
                        .buttonStyle(.borderedProminent)
                }
            case .succeeded, .failed, .cancelled:
                Spacer()
                Button {
                    dispatcher.reset()
                } label: {
                    Label("New run", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                Button("Close") { dismissSheet() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func dismissSheet() {
        dismiss()
    }

    private var elapsedString: String {
        let total = elapsedSeconds
        if total < 1 {
            return "00:00"
        }
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var commandPreview: String {
        if !dispatcher.displayedCommand.isEmpty {
            return dispatcher.displayedCommand
        }
        do {
            let command = try AgentAdapterFactory
                .makeAdapter(providerID: plan.providerID)
                .buildCommand(
                    prompt: plan.prompt,
                    projectPath: RunDispatcher.effectiveWorkingPath(for: plan),
                    mode: plan.mode,
                    provider: plan.providerSnapshot
                )
            return command.displayCommand
        } catch {
            return error.localizedDescription
        }
    }
}

private struct ScoreBar: View {
    let label: String
    let value: Double

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 130, alignment: .leading)
            ProgressView(value: value)
            Text(value.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.monospacedDigit())
                .frame(width: 48, alignment: .trailing)
        }
    }
}

/// Phase 7.2: per-rating button used inside the approval-sheet outcome
/// rating grid. When `isAISuggested` is true the button picks up the
/// accent tint and a sparkles glyph so the user can see at a glance which
/// rating Apple Foundation Models picked, while the manual choice still
/// wins on tap.
private struct AccuracyRatingButton: View {
    let rating: AccuracyRating
    let isAISuggested: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(rating.rawValue)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                if isAISuggested {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(isAISuggested ? Color.accentColor : nil)
    }
}

private struct StatusPill: View {
    let status: RunDispatcher.LiveStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 1))
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch status {
        case .idle: .secondary
        case .preparing: .blue
        case .running: .accentColor
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .orange
        }
    }
}

private struct LogLineView: View {
    let line: RunDispatcher.LogLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(prefix)
                .font(.caption.monospaced())
                .foregroundStyle(prefixColor)
                .frame(width: 22, alignment: .leading)
            Text(line.text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }

    private var prefix: String {
        switch line.kind {
        case .stdout: "›"
        case .stderr: "!"
        case .system: "·"
        }
    }

    private var prefixColor: Color {
        switch line.kind {
        case .stdout: .secondary
        case .stderr: isBenignToolingWarning ? .orange : .red
        case .system: .accentColor
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .stdout: .primary
        case .stderr: isBenignToolingWarning ? .secondary : .red
        case .system: .secondary
        }
    }

    private var isBenignToolingWarning: Bool {
        line.kind == .stderr
        && line.text.contains(" WARN codex_core_")
        && line.text.contains("ignoring interface.")
    }
}

private struct PromptRunDockRow: View {
    let session: PromptRunSession
    let onShow: () -> Void
    let onCancel: () -> Void
    let onClear: () -> Void

    private var dispatcher: RunDispatcher { session.dispatcher }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                StatusPill(status: dispatcher.status)
                Text(session.plan.providerName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(session.plan.mode.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(session.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(detailText)
                .font(.caption)
                .foregroundStyle(dispatcher.status == .failed ? .red : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    onShow()
                } label: {
                    Label("Console", systemImage: "terminal")
                }
                .buttonStyle(.bordered)

                if dispatcher.status == .running || dispatcher.status == .preparing {
                    Button(role: .destructive) {
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                }

                if dispatcher.status.isTerminal {
                    Spacer()
                    Button(role: .destructive) {
                        onClear()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(10)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.24), lineWidth: 1)
        )
    }

    private var detailText: String {
        if let error = dispatcher.lastError {
            return error
        }
        if let last = dispatcher.logs.last(where: { !$0.text.isEmpty }) {
            return last.text
        }
        if !dispatcher.displayedCommand.isEmpty {
            return dispatcher.displayedCommand
        }
        let trimmed = session.plan.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 180 { return trimmed }
        return String(trimmed.prefix(180)) + "…"
    }
}

private struct WizardTarget: Identifiable {
    let id: String
    let provider: AgentProviderProfile
}

private struct ProviderSetupView: View {
    @Environment(\.modelContext) private var modelContext
    let providers: [AgentProviderProfile]
    @Query private var setups: [ProviderSetupRecord]
    @Query private var keychainReferences: [KeychainReferenceRecord]

    @State private var isProbing = false
    @State private var probingProviderIDs: Set<String> = []
    @State private var statusText = "Installers are never run silently. Copy commands after reviewing the provider source."
    @State private var wizardTarget: WizardTarget?

    private var badgeSummariesByProvider: [String: ProviderSetupBadgeSummary] {
        Dictionary(
            uniqueKeysWithValues: ProviderSetupBadgeBuilder.summaries(
                providers: providers,
                setups: setups,
                keychainReferences: keychainReferences
            ).map { ($0.providerID, $0) }
        )
    }

    private var orderedProviders: [AgentProviderProfile] {
        let catalogOrder = Dictionary(
            uniqueKeysWithValues: ProviderCatalog.defaultProfiles.enumerated().map { index, draft in
                (draft.identifier, index)
            }
        )

        return providers.sorted { lhs, rhs in
            let lhsTone = badgeSummariesByProvider[lhs.identifier]?.overallTone ?? .healthy
            let rhsTone = badgeSummariesByProvider[rhs.identifier]?.overallTone ?? .healthy
            if lhsTone != rhsTone {
                return lhsTone < rhsTone
            }

            let lhsIndex = catalogOrder[lhs.identifier] ?? Int.max
            let rhsIndex = catalogOrder[rhs.identifier] ?? Int.max
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }

            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Provider Setup")
                            .font(.largeTitle.weight(.semibold))
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        probeProviders()
                    } label: {
                        Label(isProbing ? "Probing" : "Probe Local CLIs", systemImage: "waveform.path.ecg")
                    }
                    .disabled(isProbing)
                }

                ForEach(orderedProviders, id: \.identifier) { provider in
                    ProviderProfileRow(
                        provider: provider,
                        badgeSummary: badgeSummariesByProvider[provider.identifier],
                        isReprobing: probingProviderIDs.contains(provider.identifier),
                        onReprobe: {
                            probeProvider(provider)
                        }
                    ) {
                        wizardTarget = WizardTarget(id: provider.identifier, provider: provider)
                    }
                }
            }
            .padding(24)
        }
        .sheet(item: $wizardTarget) { target in
            ProviderSetupSheet(provider: target.provider) { resultMessage in
                wizardTarget = nil
                if let resultMessage {
                    statusText = resultMessage
                }
            }
        }
    }

    private func probeProviders() {
        isProbing = true
        statusText = "Checking CLI availability, versions, and local command paths."

        Task { @MainActor in
            for provider in providers {
                let health = await AppServices.healthMonitor.probe(provider: provider.snapshot())
                apply(health: health, to: provider)
            }

            do {
                try modelContext.save()
                await AppServices.cloudSync.recordLocalSave()
                statusText = "Provider probe complete."
            } catch {
                statusText = "Provider probe saved locally with error: \(error.localizedDescription)"
            }
            isProbing = false
        }
    }

    private func probeProvider(_ provider: AgentProviderProfile) {
        let providerID = provider.identifier
        probingProviderIDs.insert(providerID)
        statusText = "Re-probing \(provider.displayName) for badge remediation."

        Task { @MainActor in
            let health = await AppServices.healthMonitor.probe(provider: provider.snapshot())
            apply(health: health, to: provider)

            do {
                try modelContext.save()
                await AppServices.cloudSync.recordLocalSave()
                statusText = "\(provider.displayName) re-probe complete."
            } catch {
                statusText = "\(provider.displayName) re-probe saved locally with error: \(error.localizedDescription)"
            }
            probingProviderIDs.remove(providerID)
        }
    }

    private func apply(health: ProviderHealthSnapshot, to provider: AgentProviderProfile) {
        provider.installedState = health.availabilityState.rawValue
        if health.authStatus == .accountSignedIn || health.authStatus == .apiKeyPresent || health.authStatus == .customProfile || health.authStatus == .notRequired {
            provider.authState = ProviderAuthState.authenticated.rawValue
        }
        provider.lastDetectedVersion = health.detectedVersion
        provider.lastHealthCheckAt = health.checkedAt
        provider.updatedAt = health.checkedAt
    }
}

private struct ProviderProfileRow: View {
    let provider: AgentProviderProfile
    let badgeSummary: ProviderSetupBadgeSummary?
    let isReprobing: Bool
    let onReprobe: () -> Void
    let onSetup: () -> Void

    private var freshnessBadge: ProviderSetupBadge? {
        badgeSummary?.badge(of: .freshness)
    }

    private var shouldOfferReprobe: Bool {
        guard let freshnessBadge else { return false }
        return freshnessBadge.tone != .healthy
    }

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(provider.displayName)
                            .font(.headline)
                        Text(provider.providerFamily)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let badgeSummary {
                        ProviderSetupBadgeStrip(summary: badgeSummary)
                            .accessibilityIdentifier("ProviderRow.\(provider.identifier).Badges")
                    } else {
                        ProviderStatusBadge(title: provider.installedState)
                        ProviderStatusBadge(title: provider.authState)
                    }
                }

                if let badgeSummary, badgeSummary.overallTone != .healthy {
                    Text(badgeSummary.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("ProviderRow.\(provider.identifier).BadgeSummary")
                }

                Text(provider.capabilities.replacingOccurrences(of: ",", with: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Install") {
                    CommandCopyView(command: provider.installCommand)
                }

                LabeledContent("Verify") {
                    CommandCopyView(command: provider.verificationCommand)
                }

                LabeledContent("Auth") {
                    Text(provider.authGuide)
                        .foregroundStyle(.secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        providerDocsLink
                        Spacer()
                        providerActionButtons
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        providerDocsLink
                        HStack(spacing: 10) {
                            providerActionButtons
                        }
                    }
                }
                Text(provider.safetyNotes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var providerDocsLink: some View {
        Link("Provider Docs", destination: URL(string: provider.sourceURL) ?? URL(string: "https://example.com")!)
    }

    private var providerActionButtons: some View {
        Group {
            if shouldOfferReprobe {
                Button {
                    onReprobe()
                } label: {
                    Label(isReprobing ? "Re-probing…" : "Re-probe", systemImage: "waveform.path.ecg")
                }
                .disabled(isReprobing)
                .buttonStyle(.bordered)
                .help(freshnessBadge?.remediation ?? freshnessBadge?.detail ?? "Run provider probe")
                .accessibilityIdentifier("ProviderRow.\(provider.identifier).Reprobe")
            }
            Button {
                onSetup()
            } label: {
                Label("Set up…", systemImage: "wand.and.rays")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("ProviderRow.\(provider.identifier).Setup")
        }
    }
}

private struct ProviderSetupSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let provider: AgentProviderProfile
    let onClose: (String?) -> Void

    enum Step: Int, CaseIterable, Hashable, Identifiable {
        case install, authenticate, customProfile, verify

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .install: "Install"
            case .authenticate: "Authenticate"
            case .customProfile: "Custom Profile"
            case .verify: "Verify"
            }
        }

        var systemImage: String {
            switch self {
            case .install: "shippingbox"
            case .authenticate: "key"
            case .customProfile: "terminal"
            case .verify: "checkmark.seal"
            }
        }
    }

    @State private var step: Step = .install
    @State private var probeStatus: String = "Not probed yet."
    @State private var probeResult: ProviderHealthSnapshot?
    @State private var probing: Bool = false

    // Auth fields
    @State private var apiKeyInput: String = ""
    @State private var apiKeyStored: Bool = false
    @State private var apiKeyStatus: String = ""
    @State private var oauthURL: String = ""
    @State private var oauthCallbackScheme: String = ""
    @State private var oauthStatus: String = ""
    @State private var envVarName: String = ""
    @State private var envVarValue: String = ""

    // Profile fields
    @State private var profileExecutableOverride: String = ""
    @State private var profileArgumentTemplate: String = ""
    @State private var profileEnvironmentJSON: String = "{}"
    @State private var profileNotes: String = ""
    @State private var profileEnabled: Bool = false
    @State private var profileLoaded: Bool = false
    @State private var profileStatus: String = ""

    @State private var oauthCoordinator = OAuthSignInCoordinator()

    private var authRecipe: ProviderAuthRecipe {
        ProviderAuthRecipe.recipe(for: provider.identifier)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)

            stepIndicator
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                Group {
                    switch step {
                    case .install: installStep
                    case .authenticate: authenticateStep
                    case .customProfile: customProfileStep
                    case .verify: verifyStep
                    }
                }
                .padding(24)
            }

            Divider()

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 620, idealHeight: 700)
        .background(.regularMaterial)
        .task {
            await loadProfileFromContext()
            await refreshAPIKeyState()
        }
    }

    // MARK: Header / indicator / footer

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(provider.displayName)
                    .font(.title2.weight(.semibold))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(provider.providerFamily)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(step.title)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 1))
            }
            Text("Walk through install, authentication, custom command profile, and verification. No installer ever runs silently.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepIndicator: some View {
        HStack(spacing: 12) {
            ForEach(Step.allCases) { value in
                Button {
                    step = value
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: value.systemImage)
                        Text(value.title)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(value == step ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(value == step ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1))
                    .foregroundStyle(value == step ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            Button("Close") {
                onClose(nil)
                dismiss()
            }
            Spacer()
            if let previous = step.previous {
                Button("Back") { step = previous }
            }
            if let next = step.next {
                Button {
                    step = next
                } label: {
                    Label("Next", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    onClose("Setup complete for \(provider.displayName).")
                    dismiss()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Step 1 – Install

    @ViewBuilder
    private var installStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Install command")
                        .font(.headline)
                    Text("Copy and run this in Terminal — Agenic Load-Balancer never executes installers silently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CommandCopyView(command: provider.installCommand)
                    LabeledContent("Verify") {
                        CommandCopyView(command: provider.verificationCommand)
                    }
                    LabeledContent("Expected binary", value: provider.binaryName)
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Detection")
                        .font(.headline)
                    HStack {
                        Button {
                            probe()
                        } label: {
                            Label(probing ? "Probing…" : "Probe now", systemImage: "waveform.path.ecg")
                        }
                        .disabled(probing)
                        Spacer()
                    }
                    Text(probeStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let probeResult, let version = probeResult.detectedVersion {
                        LabeledContent("Detected version", value: version)
                    }
                }
            }
        }
    }

    // MARK: Step 2 – Authenticate

    @ViewBuilder
    private var authenticateStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provider auth guide")
                        .font(.headline)
                    Text(authRecipe.primaryMethod)
                        .font(.callout)
                    Text(authRecipe.billingBoundary)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(provider.authGuide)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Methods: \(provider.authMethods)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    HStack {
                        Button {
                            openProviderAuthDocs()
                        } label: {
                            Label("Provider Docs", systemImage: "safari")
                        }
                        Spacer()
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Account / browser sign-in")
                        .font(.headline)
                    Text(authRecipe.directOAuthNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if authRecipe.accountLoginCommands.isEmpty {
                        Label("No provider-managed browser login is registered for this provider.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(authRecipe.accountLoginCommands) { command in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(command.title)
                                    .font(.subheadline.weight(.medium))
                                Text(command.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                CommandCopyView(command: command.command)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    if !authRecipe.authProbeCommands.isEmpty {
                        Divider()
                        Text("Auth probes")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        ForEach(authRecipe.authProbeCommands) { command in
                            LabeledContent(command.title) {
                                CommandCopyView(command: command.command)
                            }
                        }
                    }
                    HStack {
                        Button {
                            markAccountLoginComplete()
                        } label: {
                            Label("Mark account login complete", systemImage: "checkmark.seal")
                        }
                        Spacer()
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("API key")
                        .font(.headline)
                    Text("Stored only in the macOS Keychain (genericPassword). SwiftData/CloudKit hold a reference, never the secret.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !authRecipe.apiKeyEnvironmentVariables.isEmpty {
                        Text("Known env keys: \(authRecipe.apiKeyEnvironmentVariables.joined(separator: ", "))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    SecureField("Paste API key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button {
                            saveAPIKey()
                        } label: {
                            Label("Save to Keychain", systemImage: "lock.fill")
                        }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        if apiKeyStored {
                            Button(role: .destructive) {
                                clearAPIKey()
                            } label: {
                                Label("Remove stored key", systemImage: "lock.slash")
                            }
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                        if apiKeyStored {
                            Label("Key on file", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Color.green)
                                .font(.caption)
                        }
                    }
                    if !apiKeyStatus.isEmpty {
                        Text(apiKeyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Advanced direct OAuth callback")
                        .font(.headline)
                    Text(authRecipe.directOAuthSupported ? "Opens an ASWebAuthenticationSession when a provider publishes a direct authorize URL for this app." : "Most configured providers own their browser/device login inside the CLI. Use this only for a custom provider that gives you an authorize URL and callback scheme.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Authorise URL (https://…)", text: $oauthURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Callback URL scheme (e.g. agenic-codex)", text: $oauthCallbackScheme)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button {
                            startOAuth()
                        } label: {
                            Label("Sign in via browser", systemImage: "safari")
                        }
                        .disabled(URL(string: oauthURL) == nil || oauthCallbackScheme.isEmpty)
                        Spacer()
                        if !oauthStatus.isEmpty {
                            Text(oauthStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Environment variable hint")
                        .font(.headline)
                    Text("If your provider only consults a shell environment variable, supply name + value here and they'll be persisted into the custom command profile in the next step.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Variable name (e.g. OPENAI_API_KEY)", text: $envVarName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Value", text: $envVarValue)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Button {
                            applyEnvVarToProfile()
                        } label: {
                            Label("Add to profile", systemImage: "plus.rectangle")
                        }
                        .disabled(envVarName.isEmpty)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: Step 3 – Custom command profile

    @ViewBuilder
    private var customProfileStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Command profile")
                        .font(.headline)
                    Text("Override the executable, argument template, and environment for this provider. Placeholders {{prompt}} {{project}} {{mode}} {{provider_id}} are substituted at run time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Enable custom profile", isOn: $profileEnabled)
                        .toggleStyle(.switch)
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Executable")
                        .font(.headline)
                    TextField("Optional executable path override", text: $profileExecutableOverride)
                        .textFieldStyle(.roundedBorder)
                    Text("Leave blank to use the catalog `\(provider.binaryName)` resolved from PATH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Argument template")
                        .font(.headline)
                    Text("One argument per line. Empty lines are ignored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $profileArgumentTemplate)
                        .font(.callout.monospaced())
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.separator.opacity(0.4), lineWidth: 1)
                        )
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Environment (JSON)")
                        .font(.headline)
                    Text("`{ \"OPENAI_API_KEY\": \"...\" }`. Stored alongside the profile; secrets you paste here are not encrypted — prefer the API-key step which writes to Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $profileEnvironmentJSON)
                        .font(.callout.monospaced())
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.separator.opacity(0.4), lineWidth: 1)
                        )
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.headline)
                    TextField("Optional notes (purpose, gotchas, manual steps)", text: $profileNotes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                    HStack {
                        Button {
                            saveProfile()
                        } label: {
                            Label("Save profile", systemImage: "tray.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Reset to catalog default") {
                            applyDefaultProfileTemplate()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        if !profileStatus.isEmpty {
                            Text(profileStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Step 4 – Verify

    @ViewBuilder
    private var verifyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recheck availability")
                        .font(.headline)
                    HStack {
                        Button {
                            probe()
                        } label: {
                            Label(probing ? "Probing…" : "Re-run probe", systemImage: "waveform.path.ecg")
                        }
                        .disabled(probing)
                        Spacer()
                    }
                    LabeledContent("Status", value: probeResult?.availabilityState.rawValue.capitalized ?? "Unknown")
                    if let probeResult {
                        LabeledContent("Auth", value: probeResult.authStatus.label)
                        LabeledContent("Limits", value: probeResult.limitStatus.label)
                    }
                    if let detectedVersion = probeResult?.detectedVersion {
                        LabeledContent("Version", value: detectedVersion)
                    }
                    Text(probeStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.headline)
                    LabeledContent("Provider", value: "\(provider.displayName) (\(provider.identifier))")
                    LabeledContent("Installed state", value: provider.installedState)
                    LabeledContent("Auth state", value: provider.authState)
                    LabeledContent("API key", value: apiKeyStored ? "Stored in Keychain" : "Not stored")
                    LabeledContent("Custom profile", value: profileEnabled ? "Enabled" : "Disabled")
                }
            }
        }
    }

    // MARK: Actions

    private func probe() {
        probing = true
        probeStatus = "Checking PATH…"
        let snapshot = provider.snapshot()
        Task { @MainActor in
            let health = await AppServices.healthMonitor.probe(provider: snapshot)
            probeResult = health
            let report = ProviderProbeClassifier.report(
                provider: snapshot,
                health: health,
                usage: nil,
                reliability: nil
            )
            probeStatus = "\(health.message) \(report.summary)"
            provider.installedState = health.availabilityState.rawValue
            if health.authStatus == .accountSignedIn || health.authStatus == .apiKeyPresent || health.authStatus == .customProfile || health.authStatus == .notRequired {
                provider.authState = ProviderAuthState.authenticated.rawValue
            }
            provider.lastDetectedVersion = health.detectedVersion
            provider.lastHealthCheckAt = health.checkedAt
            provider.updatedAt = health.checkedAt
            try? modelContext.save()
            probing = false
        }
    }

    private func saveAPIKey() {
        let secret = apiKeyInput.trimmingCharacters(in: .whitespaces)
        let providerID = provider.identifier
        let providerName = provider.displayName
        Task { @MainActor in
            do {
                let result = try await AppServices.setupWizard.saveAPIKey(
                    for: providerID,
                    apiKey: secret,
                    purpose: "\(providerName) API key"
                )
                upsertKeychainReference(result: result, providerID: providerID)
                provider.authState = ProviderAuthState.authenticated.rawValue
                provider.updatedAt = Date()
                try modelContext.save()
                apiKeyStored = true
                apiKeyStatus = "Saved as \(result.account)@\(result.service)."
                apiKeyInput = ""
            } catch {
                apiKeyStatus = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func clearAPIKey() {
        let providerID = provider.identifier
        Task { @MainActor in
            await AppServices.setupWizard.clearAPIKey(for: providerID)
            removeKeychainReferences(providerID: providerID)
            provider.authState = ProviderAuthState.unauthenticated.rawValue
            provider.updatedAt = Date()
            try? modelContext.save()
            apiKeyStored = false
            apiKeyStatus = "Removed stored key."
        }
    }

    private func startOAuth() {
        guard let url = URL(string: oauthURL), !oauthCallbackScheme.isEmpty else {
            oauthStatus = "Provide a valid URL and callback scheme."
            return
        }
        oauthStatus = "Browser sign-in in progress…"
        let coordinator = oauthCoordinator
        Task { @MainActor in
            do {
                let callback = try await coordinator.start(url: url, callbackScheme: oauthCallbackScheme)
                provider.authState = ProviderAuthState.authenticated.rawValue
                provider.updatedAt = Date()
                try? modelContext.save()
                oauthStatus = "Sign-in complete (callback host: \(callback.host ?? "n/a"))."
            } catch {
                oauthStatus = "OAuth failed: \(error.localizedDescription)"
            }
        }
    }

    private func openProviderAuthDocs() {
        let target = authRecipe.docsURL.isEmpty ? provider.sourceURL : authRecipe.docsURL
        guard let url = URL(string: target) else { return }
        NSWorkspace.shared.open(url)
    }

    private func markAccountLoginComplete() {
        provider.authState = ProviderAuthState.authenticated.rawValue
        provider.updatedAt = Date()
        do {
            try modelContext.save()
            oauthStatus = "Account login marked authenticated for routing and dashboard setup."
            Task { await AppServices.cloudSync.recordLocalSave() }
        } catch {
            oauthStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func applyEnvVarToProfile() {
        var env = parseProfileEnv()
        env[envVarName] = envVarValue
        let encoded = (try? JSONEncoder().encode(env)).flatMap { String(data: $0, encoding: .utf8) }
        profileEnvironmentJSON = encoded ?? profileEnvironmentJSON
        envVarName = ""
        envVarValue = ""
        step = .customProfile
    }

    private func saveProfile() {
        let providerID = provider.identifier
        let providerName = provider.displayName
        let exec = profileExecutableOverride.trimmingCharacters(in: .whitespaces)
        let template = profileArgumentTemplate
        let envJSON = sanitizeEnvironmentJSON(profileEnvironmentJSON)
        let isEnabled = profileEnabled
        let notes = profileNotes
        let displayName = "\(providerName) custom profile"

        Task { @MainActor in
            do {
                let descriptor = FetchDescriptor<ProviderCommandProfile>()
                let existing = try modelContext.fetch(descriptor).first { $0.providerID == providerID }
                if let existing {
                    existing.displayName = displayName
                    existing.executablePathOverride = exec.isEmpty ? nil : exec
                    existing.argumentTemplate = template
                    existing.environmentJSON = envJSON
                    existing.isEnabled = isEnabled
                    existing.notes = notes
                    existing.updatedAt = Date()
                } else {
                    let record = ProviderCommandProfile(
                        providerID: providerID,
                        displayName: displayName,
                        executablePathOverride: exec.isEmpty ? nil : exec,
                        argumentTemplate: template,
                        environmentJSON: envJSON,
                        isEnabled: isEnabled,
                        notes: notes
                    )
                    modelContext.insert(record)
                }
                try modelContext.save()
                profileStatus = "Profile saved."
            } catch {
                profileStatus = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func applyDefaultProfileTemplate() {
        let snapshot = provider.snapshot()
        Task { @MainActor in
            let draft = AppServices.setupWizard.defaultCommandProfileDraft(for: snapshot)
            profileExecutableOverride = draft.executablePathOverride ?? ""
            profileArgumentTemplate = draft.argumentTemplate
            profileEnvironmentJSON = draft.environmentJSON
            profileNotes = draft.notes
            profileEnabled = draft.isEnabled
            profileStatus = "Reset to catalog default."
        }
    }

    private func loadProfileFromContext() async {
        let providerID = provider.identifier
        let snapshot = provider.snapshot()
        let descriptor = FetchDescriptor<ProviderCommandProfile>()
        let existing = (try? modelContext.fetch(descriptor))?.first { $0.providerID == providerID }
        if let existing {
            profileExecutableOverride = existing.executablePathOverride ?? ""
            profileArgumentTemplate = existing.argumentTemplate
            profileEnvironmentJSON = existing.environmentJSON
            profileNotes = existing.notes
            profileEnabled = existing.isEnabled
            profileLoaded = true
        } else {
            let draft = AppServices.setupWizard.defaultCommandProfileDraft(for: snapshot)
            profileExecutableOverride = draft.executablePathOverride ?? ""
            profileArgumentTemplate = draft.argumentTemplate
            profileEnvironmentJSON = draft.environmentJSON
            profileNotes = draft.notes
            profileEnabled = draft.isEnabled
            profileLoaded = true
        }
    }

    private func refreshAPIKeyState() async {
        let providerID = provider.identifier
        let stored = await AppServices.setupWizard.hasStoredAPIKey(for: providerID)
        apiKeyStored = stored
    }

    // MARK: Helpers

    private func upsertKeychainReference(result: APIKeySaveResult, providerID: String) {
        let descriptor = FetchDescriptor<KeychainReferenceRecord>()
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        if let existing = matches.first(where: { $0.providerID == providerID && $0.serviceName == result.service }) {
            existing.accountName = result.account
            existing.purpose = result.purpose
            existing.updatedAt = Date()
        } else {
            let record = KeychainReferenceRecord(
                providerID: providerID,
                serviceName: result.service,
                accountName: result.account,
                purpose: result.purpose
            )
            modelContext.insert(record)
        }
    }

    private func removeKeychainReferences(providerID: String) {
        let descriptor = FetchDescriptor<KeychainReferenceRecord>()
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        for record in matches where record.providerID == providerID {
            modelContext.delete(record)
        }
    }

    private func parseProfileEnv() -> [String: String] {
        guard let data = profileEnvironmentJSON.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    /// Round-trip the JSON through the decoder so users can paste arbitrary
    /// formatted JSON and we store a canonical re-encoding (or leave the
    /// original text intact if it's not valid JSON — we still surface a
    /// note via the `profileStatus` UI later).
    private func sanitizeEnvironmentJSON(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "{}" }
        guard let data = trimmed.data(using: .utf8),
              let parsed = try? JSONDecoder().decode([String: String].self, from: data),
              let reencoded = try? JSONEncoder().encode(parsed),
              let string = String(data: reencoded, encoding: .utf8)
        else {
            return raw
        }
        return string
    }
}

private extension ProviderSetupSheet.Step {
    var previous: ProviderSetupSheet.Step? {
        ProviderSetupSheet.Step(rawValue: rawValue - 1)
    }

    var next: ProviderSetupSheet.Step? {
        ProviderSetupSheet.Step(rawValue: rawValue + 1)
    }
}

private struct ProjectEditorTarget: Identifiable {
    let id: String
    let project: AgentProject

    init(project: AgentProject) {
        self.id = project.identifier
        self.project = project
    }
}

private struct ProjectSettingsDraft {
    var name: String
    var rootPath: String?
    var bookmarkData: Data?
    var promptExcerptSyncEnabled: Bool
    var defaultWorkingPath: String?
    var temporaryWorkingPath: String?
    var allowToolCalling: Bool
    var allowShellTools: Bool
    var allowNetworkSearch: Bool
    var allowFilesystemWrites: Bool
    var contextCompactionEnabled: Bool
    var contextCompactionThresholdTokens: Int
}

private struct ProjectRow: View {
    let project: AgentProject
    let regenerateAgentNotes: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    let syncChanged: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    ProviderStatusBadge(title: project.promptExcerptSyncEnabled ? "Prompt excerpts sync" : "Prompt excerpts local")
                }

                Text(project.rootPath ?? "No folder selected")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                projectControls
            }
        }
    }

    private var projectControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                regenerateButton
                settingsButton
                promptExcerptToggle

                Spacer(minLength: 8)
                deleteButton
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    regenerateButton
                    settingsButton
                    deleteButton
                }
                promptExcerptToggle
            }
        }
    }

    private var regenerateButton: some View {
        Button {
            regenerateAgentNotes()
        } label: {
            Label("Regenerate AgentNotes", systemImage: "arrow.clockwise")
        }
        .accessibilityIdentifier("ProjectRow.\(project.identifier).Regenerate")
    }

    private var settingsButton: some View {
        Button {
            edit()
        } label: {
            Label("Settings", systemImage: "slider.horizontal.3")
        }
        .accessibilityIdentifier("ProjectRow.\(project.identifier).Settings")
    }

    private var promptExcerptToggle: some View {
        Toggle("Sync prompt excerpts", isOn: Binding(
                get: { project.promptExcerptSyncEnabled },
                set: { newValue in syncChanged(newValue) }
        ))
        .toggleStyle(.switch)
        .accessibilityIdentifier("ProjectRow.\(project.identifier).PromptExcerptSync")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            delete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("ProjectRow.\(project.identifier).Delete")
    }
}

private struct ProjectSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let project: AgentProject
    let onSave: (ProjectSettingsDraft) -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var rootPath: String?
    @State private var bookmarkData: Data?
    @State private var promptExcerptSyncEnabled: Bool
    @State private var defaultWorkingPath: String
    @State private var temporaryWorkingPath: String
    @State private var allowToolCalling: Bool
    @State private var allowShellTools: Bool
    @State private var allowNetworkSearch: Bool
    @State private var allowFilesystemWrites: Bool
    @State private var contextCompactionEnabled: Bool
    @State private var contextCompactionThresholdTokens: Int

    init(
        project: AgentProject,
        onSave: @escaping (ProjectSettingsDraft) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.project = project
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: project.name)
        _rootPath = State(initialValue: project.rootPath)
        _bookmarkData = State(initialValue: project.bookmarkData)
        _promptExcerptSyncEnabled = State(initialValue: project.promptExcerptSyncEnabled)
        _defaultWorkingPath = State(initialValue: project.defaultWorkingPath ?? project.rootPath ?? "")
        _temporaryWorkingPath = State(initialValue: project.temporaryWorkingPath ?? "")
        _allowToolCalling = State(initialValue: project.allowToolCalling)
        _allowShellTools = State(initialValue: project.allowShellTools)
        _allowNetworkSearch = State(initialValue: project.allowNetworkSearch)
        _allowFilesystemWrites = State(initialValue: project.allowFilesystemWrites)
        _contextCompactionEnabled = State(initialValue: project.contextCompactionEnabled)
        _contextCompactionThresholdTokens = State(initialValue: project.contextCompactionThresholdTokens)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            accessibilityMarker("Sheet.ProjectSettings")

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project Settings")
                        .font(.title2.weight(.semibold))
                    Text(project.name)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassPanel {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Workspace")
                                    .font(.headline)
                                TextField("Name", text: $name)
                                LabeledContent("Folder") {
                                    HStack(spacing: 8) {
                                        Text(rootPath ?? "No folder selected")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                        Button {
                                            chooseFolder()
                                        } label: {
                                            Label("Choose", systemImage: "folder")
                                        }
                                    }
                                }
                                LabeledContent("AgentNotes", value: project.agentNotesRelativePath)
                            }
                        }

                        GlassPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Recall & Sync")
                                    .font(.headline)
                                Toggle("Sync prompt excerpts for this project", isOn: $promptExcerptSyncEnabled)
                                    .toggleStyle(.switch)
                                Text("Project name, folder bookmark, AgentNotes metadata, and recall settings are stored in SwiftData and backed by the app's private CloudKit container.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        GlassPanel {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Execution")
                                    .font(.headline)
                                LabeledContent("Default working path") {
                                    HStack(spacing: 8) {
                                        TextField("Uses workspace root when blank", text: $defaultWorkingPath)
                                            .textFieldStyle(.roundedBorder)
                                        Button {
                                            defaultWorkingPath = rootPath ?? ""
                                        } label: {
                                            Label("Root", systemImage: "folder")
                                        }
                                    }
                                }
                                LabeledContent("Temporary path") {
                                    HStack(spacing: 8) {
                                        TextField("Optional TMPDIR / AGENIC_TMPDIR", text: $temporaryWorkingPath)
                                            .textFieldStyle(.roundedBorder)
                                        Button {
                                            chooseTemporaryFolder()
                                        } label: {
                                            Label("Choose", systemImage: "folder")
                                        }
                                    }
                                }
                                Toggle("Compact long run context before AI summaries", isOn: $contextCompactionEnabled)
                                    .toggleStyle(.switch)
                                Stepper(value: $contextCompactionThresholdTokens, in: 8_000...1_000_000, step: 8_000) {
                                    LabeledContent("Compaction threshold", value: "\(contextCompactionThresholdTokens.formatted()) tokens")
                                }
                            }
                        }

                        GlassPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Tool Permissions")
                                    .font(.headline)
                                Toggle("Allow tool calling", isOn: $allowToolCalling)
                                    .toggleStyle(.switch)
                                Toggle("Allow shell tools", isOn: $allowShellTools)
                                    .toggleStyle(.switch)
                                Toggle("Allow network search", isOn: $allowNetworkSearch)
                                    .toggleStyle(.switch)
                                Toggle("Allow filesystem writes", isOn: $allowFilesystemWrites)
                                    .toggleStyle(.switch)
                                Text("These values are injected into approved runs as workspace policy text and environment flags, then synced with the project record.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                Divider()

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete Project", systemImage: "trash")
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button {
                        onSave(ProjectSettingsDraft(
                            name: name,
                            rootPath: rootPath,
                            bookmarkData: bookmarkData,
                            promptExcerptSyncEnabled: promptExcerptSyncEnabled,
                            defaultWorkingPath: normalizedOptionalPath(defaultWorkingPath),
                            temporaryWorkingPath: normalizedOptionalPath(temporaryWorkingPath),
                            allowToolCalling: allowToolCalling,
                            allowShellTools: allowShellTools,
                            allowNetworkSearch: allowNetworkSearch,
                            allowFilesystemWrites: allowFilesystemWrites,
                            contextCompactionEnabled: contextCompactionEnabled,
                            contextCompactionThresholdTokens: contextCompactionThresholdTokens
                        ))
                        dismiss()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(24)
            }
        }
        .frame(minWidth: 600, idealWidth: 680, minHeight: 460, idealHeight: 560)
        .background(.regularMaterial)
    }

    private func accessibilityMarker(_ identifier: String) -> some View {
        Text(identifier)
            .font(.caption2)
            .opacity(0.01)
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(identifier)
    }

    private func normalizedOptionalPath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if let rootPath {
            panel.directoryURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        rootPath = url.path
        bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func chooseTemporaryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Temporary Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        temporaryWorkingPath = url.path
    }
}

private struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    let projects: [AgentProject]
    let coordinationEvents: [CoordinationEventRecord]

    @State private var statusText = "Add local workspaces to enable AgentNotes coordination and per-project routing history."
    @State private var editingProject: ProjectEditorTarget?
    @State private var pendingDeleteProject: ProjectEditorTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        headerText
                        Spacer(minLength: 16)
                        addWorkspaceButton
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        headerText
                        addWorkspaceButton
                    }
                }

                if projects.isEmpty {
                    ContentUnavailableView(
                        "No projects",
                        systemImage: "folder",
                        description: Text("Add a workspace to create AgentNotes.md and start project-level orchestration.")
                    )
                } else {
                    ForEach(projects, id: \.identifier) { project in
                        ProjectRow(
                            project: project,
                            regenerateAgentNotes: { regenerateAgentNotes(for: project) },
                            edit: { editingProject = ProjectEditorTarget(project: project) },
                            delete: { pendingDeleteProject = ProjectEditorTarget(project: project) },
                            syncChanged: { newValue in
                                project.promptExcerptSyncEnabled = newValue
                                project.updatedAt = Date()
                                do {
                                    try modelContext.save()
                                    Task { await AppServices.cloudSync.recordLocalSave() }
                                } catch {
                                    statusText = "Project setting save failed: \(error.localizedDescription)"
                                }
                            }
                        )
                    }
                }
            }
            .padding(24)
        }
        .accessibilityIdentifier("Screen.Projects.Content")
        .sheet(item: $editingProject) { target in
            ProjectSettingsSheet(
                project: target.project,
                onSave: { draft in
                    saveProjectSettings(
                        target.project,
                        draft: draft
                    )
                },
                onDelete: {
                    editingProject = nil
                    pendingDeleteProject = target
                }
            )
        }
        .confirmationDialog(
            "Delete project?",
            isPresented: Binding(
                get: { pendingDeleteProject != nil },
                set: { if !$0 { pendingDeleteProject = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                if let target = pendingDeleteProject {
                    deleteProject(target.project)
                }
                pendingDeleteProject = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteProject = nil
            }
        } message: {
            Text("This removes the project from Agenic Load-Balancer. Run history and coordination records remain in the repository ledger.")
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Projects")
                .font(.largeTitle.weight(.semibold))
            Text(statusText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addWorkspaceButton: some View {
        Button {
            addProject()
        } label: {
            Label("Add Workspace", systemImage: "folder.badge.plus")
        }
        .fixedSize()
        .accessibilityIdentifier("Projects.AddWorkspace")
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Workspace"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let project = AgentProject(
            name: url.lastPathComponent,
            rootPath: url.path,
            bookmarkData: try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        )
        modelContext.insert(project)

        do {
            try modelContext.save()
            Task { await AppServices.cloudSync.recordLocalSave() }
            let projectName = project.name
            let rootPath = url.path
            let events = coordinationEvents.map { $0.snapshot() }
            Task {
                let result = try? await AppServices.coordination.ensureAgentNotes(
                    projectName: projectName,
                    rootPath: rootPath,
                    events: events
                )
                await MainActor.run {
                    statusText = result?.created == true ? "Created AgentNotes.md for \(projectName)." : "Project added; AgentNotes.md already exists."
                }
            }
        } catch {
            statusText = "Project save failed: \(error.localizedDescription)"
        }
    }

    private func saveProjectSettings(
        _ project: AgentProject,
        draft: ProjectSettingsDraft
    ) {
        project.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? project.name
            : draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        project.rootPath = draft.rootPath
        project.bookmarkData = draft.bookmarkData
        project.promptExcerptSyncEnabled = draft.promptExcerptSyncEnabled
        project.defaultWorkingPath = draft.defaultWorkingPath
        project.temporaryWorkingPath = draft.temporaryWorkingPath
        project.allowToolCalling = draft.allowToolCalling
        project.allowShellTools = draft.allowShellTools
        project.allowNetworkSearch = draft.allowNetworkSearch
        project.allowFilesystemWrites = draft.allowFilesystemWrites
        project.contextCompactionEnabled = draft.contextCompactionEnabled
        project.contextCompactionThresholdTokens = draft.contextCompactionThresholdTokens
        project.updatedAt = Date()

        do {
            try modelContext.save()
            Task { await AppServices.cloudSync.recordLocalSave() }
            statusText = "Saved settings for \(project.name)."
        } catch {
            statusText = "Project setting save failed: \(error.localizedDescription)"
        }
    }

    private func deleteProject(_ project: AgentProject) {
        let name = project.name
        modelContext.delete(project)
        do {
            try modelContext.save()
            Task { await AppServices.cloudSync.recordLocalSave() }
            statusText = "Deleted project \(name)."
        } catch {
            statusText = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func regenerateAgentNotes(for project: AgentProject) {
        guard let rootPath = project.rootPath else {
            statusText = "Project has no local root path."
            return
        }
        let projectName = project.name

        let events = coordinationEvents
            .filter { $0.projectID == project.identifier || $0.projectID == nil }
            .map { $0.snapshot() }
        Task {
            let result = try? await AppServices.coordination.ensureAgentNotes(
                projectName: projectName,
                rootPath: rootPath,
                events: events
            )
            await MainActor.run {
                if result?.conflictDetected == true {
                    statusText = "AgentNotes.md has conflict markers; review before overwriting."
                } else {
                    statusText = "AgentNotes.md is present for \(projectName)."
                }
            }
        }
    }
}

private struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext

    let decisions: [RoutingDecisionRecord]
    let outcomes: [RunOutcomeRecord]
    let usageEntries: [UsageLedgerEntry]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Run History")
                    .font(.largeTitle.weight(.semibold))

                ForEach(outcomes.sorted { $0.startedAt > $1.startedAt }, id: \.identifier) { outcome in
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(outcome.providerID)
                                    .font(.headline)
                                Spacer()
                                ProviderStatusBadge(title: outcome.status)
                            }

                            Text("Run \(outcome.runID)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            HStack {
                                Text("Accuracy")
                                Spacer()
                                Menu(AccuracyRating(rawValue: outcome.accuracyRating)?.id ?? "unrated") {
                                    ForEach(AccuracyRating.allCases) { rating in
                                        Button(rating.rawValue) {
                                            outcome.accuracyRating = rating.rawValue
                                            outcome.endedAt = Date()
                                            try? modelContext.save()
                                        }
                                    }
                                }
                            }

                            if outcome.hasContinuationEvidence {
                                HistoryContinuationPanel(outcome: outcome)
                                    .accessibilityIdentifier("History.Continuation.\(outcome.runID)")
                            }
                        }
                    }
                }

                if outcomes.isEmpty {
                    ContentUnavailableView(
                        "No approved runs",
                        systemImage: "clock",
                        description: Text("Approved routing decisions and outcomes will appear here.")
                    )
                }
            }
            .padding(24)
        }
    }
}

private struct HistoryContinuationPanel: View {
    let outcome: RunOutcomeRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                Label("Continuation", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                Spacer()
                continuationChip("Depth \(outcome.continuationChainDepth)")
                continuationChip(triggerLabel)
                continuationChip(outcome.continuationRequiresApproval ? "Approval-gated" : "Auto-resume")
                if outcome.continuationWorkspaceExcerptCount > 0 {
                    continuationChip("\(outcome.continuationWorkspaceExcerptCount) excerpt(s)")
                }
            }
            Text(outcome.continuationSummary ?? outcome.continuationPolicyNote ?? "Continuation metadata captured for this run.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(.background.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
    }

    private var triggerLabel: String {
        guard let raw = outcome.continuationTriggerCategory, !raw.isEmpty else {
            return "Trigger unknown"
        }
        return ContinuationTriggerCategory(rawValue: raw)?.label ?? raw
    }

    private func continuationChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.16), in: Capsule())
    }
}

private extension RunOutcomeRecord {
    var hasContinuationEvidence: Bool {
        continuationSummary?.isEmpty == false ||
            continuationPrompt?.isEmpty == false ||
            continuationTriggerCategory?.isEmpty == false ||
            continuationPolicyNote?.isEmpty == false ||
            continuationChainDepth > 0
    }
}

private struct ArchivePreviewState: Identifiable {
    let id = UUID()
    let payload: SnapshotPayload
    let sourceLabel: String
    /// Matching `CloudSnapshotRecord` identifier when the preview originates
    /// from an in-app snapshot. `nil` for user-imported archives.
    let originSnapshotID: String?
}

private struct RestoreCenterView: View {
    @Environment(\.modelContext) private var modelContext

    let projects: [AgentProject]
    let providers: [AgentProviderProfile]
    let outcomes: [RunOutcomeRecord]
    let coordinationEvents: [CoordinationEventRecord]
    let snapshots: [CloudSnapshotRecord]
    let cloudStatus: CloudSyncStatusSnapshot

    @State private var statusText = "Create a checksummed snapshot archive on disk; restore previews compare against the live store before applying."
    @State private var previewState: ArchivePreviewState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Restore Center")
                    .font(.largeTitle.weight(.semibold))

                GlassPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Container", value: cloudStatus.containerIdentifier)
                        LabeledContent("Status", value: cloudStatus.status)
                        LabeledContent("Detail", value: cloudStatus.detail)
                        LabeledContent("Last Local Save", value: cloudStatus.lastLocalSave?.formatted(date: .abbreviated, time: .standard) ?? "Not recorded")
                        LabeledContent("Last Cloud Event", value: cloudStatus.lastCloudEvent?.formatted(date: .abbreviated, time: .standard) ?? "Not recorded")
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        createSnapshot()
                    } label: {
                        Label("Create Snapshot", systemImage: "camera.macro")
                    }
                    Button {
                        importArchive()
                    } label: {
                        Label("Import Archive…", systemImage: "tray.and.arrow.down")
                    }
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }

                if snapshots.isEmpty {
                    ContentUnavailableView(
                        "No snapshots",
                        systemImage: "clock.arrow.2.circlepath",
                        description: Text("Create a snapshot or import an existing archive to enable restore preview.")
                    )
                } else {
                    ForEach(snapshots.sorted { $0.createdAt > $1.createdAt }, id: \.identifier) { snapshot in
                        snapshotRow(for: snapshot)
                    }
                }
            }
            .padding(24)
        }
        .sheet(item: $previewState) { state in
            RestorePreviewSheet(state: state) { result in
                previewState = nil
                if let result {
                    statusText = result
                }
            }
        }
    }

    @ViewBuilder
    private func snapshotRow(for snapshot: CloudSnapshotRecord) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.scope)
                            .font(.headline)
                        Text("ID \(snapshot.identifier.prefix(8))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                Text(snapshot.recordCounts)
                    .font(.callout.monospaced())
                Text("Checksum \(snapshot.checksum.prefix(16))…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(snapshot.restoreNotes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button {
                        openPreview(for: snapshot)
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                    Button {
                        exportSnapshot(snapshot)
                    } label: {
                        Label("Export…", systemImage: "square.and.arrow.up")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        deleteSnapshot(snapshot)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: Snapshot actions

    private func createSnapshot() {
        Task { @MainActor in
            do {
                let appVersion = Self.appVersion
                let payload = try SnapshotPipeline.buildPayload(
                    from: modelContext,
                    appVersion: appVersion
                )
                let snapshotID = UUID().uuidString
                let url = try await AppServices.restore.writeArchive(
                    payload: payload,
                    identifier: snapshotID
                )

                let record = CloudSnapshotRecord(
                    identifier: snapshotID,
                    version: payload.version,
                    scope: "SwiftData master repository",
                    recordCounts: Self.formatCounts(payload.body.countsByModel),
                    checksum: payload.checksum,
                    restoreNotes: "Archive at \(url.path)",
                    status: "available",
                    createdAt: payload.createdAt
                )
                modelContext.insert(record)
                try modelContext.save()
                await AppServices.cloudSync.recordLocalSave()
                statusText = "Snapshot \(snapshotID.prefix(8)) created (\(payload.body.totalRecords) records)."
            } catch {
                statusText = "Snapshot failed: \(error.localizedDescription)"
            }
        }
    }

    private func importArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select an Agenic snapshot archive (.json)."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task { @MainActor in
            do {
                let payload = try await AppServices.restore.readArchive(at: url)
                previewState = ArchivePreviewState(
                    payload: payload,
                    sourceLabel: "Imported: \(url.lastPathComponent)",
                    originSnapshotID: nil
                )
                statusText = "Imported archive ready for preview."
            } catch {
                statusText = "Could not import archive: \(error.localizedDescription)"
            }
        }
    }

    private func openPreview(for snapshot: CloudSnapshotRecord) {
        let identifier = snapshot.identifier
        Task { @MainActor in
            do {
                let payload = try await AppServices.restore.readArchive(forIdentifier: identifier)
                previewState = ArchivePreviewState(
                    payload: payload,
                    sourceLabel: "Snapshot \(identifier.prefix(8))",
                    originSnapshotID: identifier
                )
            } catch {
                statusText = "Preview failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportSnapshot(_ snapshot: CloudSnapshotRecord) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "agenic-\(snapshot.identifier.prefix(8)).json"
        panel.message = "Save the snapshot archive to a location of your choice."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let identifier = snapshot.identifier
        Task { @MainActor in
            do {
                _ = try await AppServices.restore.exportArchive(
                    forIdentifier: identifier,
                    to: url
                )
                statusText = "Exported snapshot to \(url.lastPathComponent)."
            } catch {
                statusText = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func deleteSnapshot(_ snapshot: CloudSnapshotRecord) {
        let identifier = snapshot.identifier
        Task { @MainActor in
            do {
                try await AppServices.restore.deleteArchive(forIdentifier: identifier)
                modelContext.delete(snapshot)
                try modelContext.save()
                statusText = "Snapshot \(identifier.prefix(8)) deleted."
            } catch {
                statusText = "Delete failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Static helpers

    private static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    private static func formatCounts(_ counts: [String: Int]) -> String {
        ModelKey.renderOrder
            .map { key in
                let label = ModelKey.displayLabels[key] ?? key
                return "\(label)=\(counts[key] ?? 0)"
            }
            .joined(separator: "; ")
    }
}

private struct RestorePreviewSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let state: ArchivePreviewState
    let onClose: (String?) -> Void

    @State private var diff: SnapshotDiff?
    @State private var statusText = "Verifying archive…"
    @State private var lastError: String?
    @State private var mergeResult: SnapshotMergeResult?
    @State private var didApply = false
    @State private var isWorking = false
    @State private var pendingReplaceConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataPanel
                    if let diff {
                        diffPanel(diff: diff)
                    } else if let lastError {
                        GlassPanel {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Archive verification failed", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(lastError)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        ProgressView("Verifying…")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                    if let mergeResult {
                        GlassPanel {
                            Label("Merged: inserted \(mergeResult.inserted), skipped \(mergeResult.skipped) existing.", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 580, idealHeight: 660)
        .background(.regularMaterial)
        .task { await computeDiff() }
        .confirmationDialog(
            "Replace live records with this archive?",
            isPresented: $pendingReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) { applyReplace() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every record currently in SwiftData and inserts the archive's records in a single save. CloudKit will propagate the change to your other devices.")
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Restore preview")
                    .font(.title2.weight(.semibold))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(state.sourceLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadgePill(text: statusText, tint: didApply ? .green : (lastError == nil ? .accentColor : .red))
            }
            Text("Restore-into-new-copy semantics: the archive is verified and diffed before any live records change.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var metadataPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Archive metadata")
                    .font(.headline)
                LabeledContent("Schema version", value: state.payload.version)
                LabeledContent("App version", value: state.payload.appVersion)
                LabeledContent("Created", value: state.payload.createdAt.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Records", value: "\(state.payload.body.totalRecords)")
                LabeledContent("Checksum") {
                    Text(state.payload.checksum)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder
    private func diffPanel(diff: SnapshotDiff) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Per-model diff")
                    .font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Model")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Archive")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        Text("Live")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        Text("Overlap")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text("New")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                    Divider()
                    ForEach(ModelKey.renderOrder, id: \.self) { key in
                        GridRow {
                            Text(ModelKey.displayLabels[key] ?? key)
                                .font(.callout)
                            Text("\(diff.archiveCounts[key] ?? 0)")
                                .font(.callout.monospacedDigit())
                                .frame(width: 70, alignment: .trailing)
                            Text("\(diff.liveCounts[key] ?? 0)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                            Text("\(diff.overlapCounts[key] ?? 0)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle((diff.overlapCounts[key] ?? 0) > 0 ? Color.orange : Color.secondary)
                                .frame(width: 80, alignment: .trailing)
                            Text("\(diff.archiveOnlyCounts[key] ?? 0)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle((diff.archiveOnlyCounts[key] ?? 0) > 0 ? Color.accentColor : Color.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                    Divider()
                    GridRow {
                        Text("Totals")
                            .font(.callout.weight(.semibold))
                        Text("\(diff.totalArchive)")
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .frame(width: 70, alignment: .trailing)
                        Text("\(diff.totalLive)")
                            .font(.callout.monospacedDigit())
                            .frame(width: 70, alignment: .trailing)
                        Text("\(diff.totalOverlap)")
                            .font(.callout.monospacedDigit())
                            .frame(width: 80, alignment: .trailing)
                        Text("\(diff.totalArchiveOnly)")
                            .font(.callout.monospacedDigit())
                            .frame(width: 60, alignment: .trailing)
                    }
                }

                Text("Replace deletes the entire live store before reinserting the archive. Merge inserts only the archive records whose identifier is not already present in the live store.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Close") {
                onClose(nil)
                dismiss()
            }
            Button {
                applyMerge()
            } label: {
                Label("Apply Merge", systemImage: "rectangle.2.swap")
            }
            .disabled(diff == nil || isWorking || didApply)
            Button {
                pendingReplaceConfirmation = true
            } label: {
                Label("Replace…", systemImage: "arrow.counterclockwise.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(diff == nil || isWorking || didApply)
        }
    }

    private func computeDiff() async {
        do {
            try SnapshotArchiveCodec.verify(state.payload)
            let computed = try SnapshotPipeline.computeDiff(
                archive: state.payload,
                against: modelContext
            )
            diff = computed
            statusText = "Verified · \(computed.totalArchive) archive vs \(computed.totalLive) live"
        } catch {
            lastError = error.localizedDescription
            statusText = "Verification failed"
        }
    }

    private func applyReplace() {
        isWorking = true
        defer { isWorking = false }
        do {
            try SnapshotPipeline.applyReplace(payload: state.payload, into: modelContext)
            didApply = true
            statusText = "Replaced live records with archive."
            Task { await AppServices.cloudSync.recordLocalSave() }
        } catch {
            lastError = error.localizedDescription
            statusText = "Replace failed."
        }
    }

    private func applyMerge() {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try SnapshotPipeline.applyMerge(payload: state.payload, into: modelContext)
            mergeResult = result
            didApply = true
            statusText = "Merged: +\(result.inserted), skipped \(result.skipped)"
            Task { await AppServices.cloudSync.recordLocalSave() }
        } catch {
            lastError = error.localizedDescription
            statusText = "Merge failed."
        }
    }
}

private struct StatusBadgePill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 1))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 360, alignment: .trailing)
    }
}

private struct AgentNotesView: View {
    @Environment(\.modelContext) private var modelContext

    let projects: [AgentProject]
    let coordinationEvents: [CoordinationEventRecord]

    @State private var reconciliations: [String: AgentNotesReconciliation] = [:]
    @State private var statusByProject: [String: String] = [:]
    @State private var mergeProposals: [String: AgentNotesMergeProposal] = [:]
    @State private var mergeInProgressProjectIDs: Set<String> = []
    @State private var resolvingStaleProjectIDs: Set<String> = []
    @State private var pendingApply: PendingApply?

    private enum ApplyKind {
        case regenerateFromSwiftData
        case mergeProposal

        var confirmTitle: String {
            switch self {
            case .regenerateFromSwiftData: "Replace"
            case .mergeProposal: "Apply Merge"
            }
        }

        var successMessage: String {
            switch self {
            case .regenerateFromSwiftData: "Regenerated AgentNotes.md from SwiftData."
            case .mergeProposal: "Applied reviewed AgentNotes merge proposal."
            }
        }

        var confirmationMessage: String {
            switch self {
            case .regenerateFromSwiftData:
                return "This regenerates AgentNotes.md from the SwiftData coordination ledger. Hand-edits will be lost. The original is also a SwiftData record so nothing is permanently destroyed."
            case .mergeProposal:
                return "This replaces AgentNotes.md with the reviewed merge proposal. A snapshot or Git checkpoint should exist before applying this to important project roots."
            }
        }
    }

    private struct PendingApply: Identifiable {
        let id = UUID()
        let projectID: String
        let projectName: String
        let rootPath: String
        let suggestedContent: String
        let kind: ApplyKind
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AgentNotes Coordination")
                    .font(.largeTitle.weight(.semibold))

                GlassPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Required Agent Preflight")
                            .font(.headline)
                        Text("Every routed agent receives the latest AgentNotes excerpt above its prompt, plus instructions to claim/update tasks and record checkpoints. SwiftData remains canonical; the file on disk is the project-visible projection.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(projects, id: \.identifier) { project in
                    AgentNotesProjectRow(
                        project: project,
                        reconciliation: reconciliations[project.identifier],
                        mergeProposal: mergeProposals[project.identifier],
                        statusText: statusByProject[project.identifier],
                        mergeInProgress: mergeInProgressProjectIDs.contains(project.identifier),
                        eventCountForProject: coordinationEvents
                            .filter { $0.projectID == project.identifier || $0.projectID == nil }
                            .count,
                        staleDispatchCount: staleDispatchEvents(for: project).count,
                        resolvingStaleDispatches: resolvingStaleProjectIDs.contains(project.identifier),
                        onReconcile: {
                            await reconcile(project: project)
                        },
                        onResolveStaleDispatches: {
                            await resolveStaleDispatches(project: project)
                        },
                        onApply: {
                            if let reconciliation = reconciliations[project.identifier] {
                                pendingApply = PendingApply(
                                    projectID: project.identifier,
                                    projectName: project.name,
                                    rootPath: project.rootPath ?? "",
                                    suggestedContent: reconciliation.suggestedContent,
                                    kind: .regenerateFromSwiftData
                                )
                            }
                        },
                        onProposeMerge: {
                            await proposeMerge(project: project)
                        },
                        onApplyMerge: {
                            if let proposal = mergeProposals[project.identifier] {
                                pendingApply = PendingApply(
                                    projectID: project.identifier,
                                    projectName: project.name,
                                    rootPath: project.rootPath ?? "",
                                    suggestedContent: proposal.mergedContent,
                                    kind: .mergeProposal
                                )
                            }
                        }
                    )
                }

                if projects.isEmpty {
                    ContentUnavailableView(
                        "No projects yet",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Add a project workspace from the Projects tab to enable AgentNotes reconciliation.")
                    )
                }

                Divider()

                ForEach(coordinationEvents.sorted { $0.createdAt > $1.createdAt }, id: \.identifier) { event in
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(event.title)
                                    .font(.headline)
                                Spacer()
                                ProviderStatusBadge(title: event.status)
                            }
                            Text("\(event.phase) / \(event.wave) / \(event.step)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(event.detail)
                                .foregroundStyle(.secondary)
                            if let commitSHA = event.commitSHA {
                                Text("Commit \(commitSHA)")
                                    .font(.caption.monospaced())
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .confirmationDialog(
            "Replace AgentNotes.md?",
            isPresented: Binding(
                get: { pendingApply != nil },
                set: { newValue in if !newValue { pendingApply = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingApply?.kind.confirmTitle ?? "Replace", role: .destructive) {
                if let target = pendingApply {
                    Task { await applyReconciliation(target: target) }
                }
            }
            Button("Cancel", role: .cancel) { pendingApply = nil }
        } message: {
            Text(pendingApply?.kind.confirmationMessage ?? "")
        }
    }

    private func reconcile(project: AgentProject) async {
        guard let rootPath = project.rootPath, !rootPath.isEmpty else {
            statusByProject[project.identifier] = "Project has no local root path."
            return
        }
        let snapshots = coordinationEvents
            .filter { $0.projectID == project.identifier || $0.projectID == nil }
            .map { $0.snapshot() }
        do {
            let result = try await AppServices.coordination.reconcile(
                projectName: project.name,
                rootPath: rootPath,
                events: snapshots
            )
            reconciliations[project.identifier] = result
            statusByProject[project.identifier] = Self.statusText(for: result)
            if !result.requiresAttention {
                mergeProposals[project.identifier] = nil
            }
        } catch {
            statusByProject[project.identifier] = "Reconcile failed: \(error.localizedDescription)"
        }
    }

    private func proposeMerge(project: AgentProject) async {
        guard let reconciliation = reconciliations[project.identifier] else {
            statusByProject[project.identifier] = "Run reconcile before requesting a merge proposal."
            return
        }
        guard let localContent = reconciliation.onDiskContent else {
            statusByProject[project.identifier] = "No on-disk AgentNotes.md content is available to merge."
            return
        }

        mergeInProgressProjectIDs.insert(project.identifier)
        defer { mergeInProgressProjectIDs.remove(project.identifier) }

        let intelligence = AgentNotesIntelligenceFactory.makeDefault()
        do {
            let proposal = try await intelligence.proposeMerge(
                localContent: localContent,
                generatedContent: reconciliation.suggestedContent
            )
            mergeProposals[project.identifier] = proposal
            if proposal.unresolvedConflicts.isEmpty {
                statusByProject[project.identifier] = "Merge proposal ready."
            } else {
                statusByProject[project.identifier] = "Merge proposal has \(proposal.unresolvedConflicts.count) unresolved conflict(s)."
            }
        } catch {
            statusByProject[project.identifier] = "Merge proposal failed: \(error.localizedDescription)"
        }
    }

    private func applyReconciliation(target: PendingApply) async {
        do {
            _ = try await AppServices.coordination.applyReconciliation(
                rootPath: target.rootPath,
                suggestedContent: target.suggestedContent
            )
            statusByProject[target.projectID] = target.kind.successMessage
            mergeProposals[target.projectID] = nil
            // Re-run the reconcile so the displayed state moves to fileMatches.
            if let project = projects.first(where: { $0.identifier == target.projectID }) {
                await reconcile(project: project)
            }
        } catch {
            statusByProject[target.projectID] = "Apply failed: \(error.localizedDescription)"
        }
        pendingApply = nil
    }

    private func staleDispatchEvents(for project: AgentProject) -> [CoordinationEventRecord] {
        CoordinationEventMaintenance.staleDispatchEvents(
            in: coordinationEvents,
            projectID: project.identifier
        )
    }

    private func resolveStaleDispatches(project: AgentProject) async {
        let targets = staleDispatchEvents(for: project)
        guard !targets.isEmpty else {
            statusByProject[project.identifier] = "No stale dispatch records to resolve."
            return
        }

        resolvingStaleProjectIDs.insert(project.identifier)
        defer { resolvingStaleProjectIDs.remove(project.identifier) }

        let resolvedCount = CoordinationEventMaintenance.resolveStaleDispatchEvents(targets)
        do {
            try modelContext.save()
            await AppServices.cloudSync.recordLocalSave()
            statusByProject[project.identifier] = "Resolved \(resolvedCount) stale dispatch record(s)."
            if let rootPath = project.rootPath, !rootPath.isEmpty {
                let snapshots = coordinationEvents
                    .filter { $0.projectID == project.identifier || $0.projectID == nil }
                    .map { $0.snapshot() }
                let reconciliation = try await AppServices.coordination.reconcile(
                    projectName: project.name,
                    rootPath: rootPath,
                    events: snapshots
                )
                _ = try await AppServices.coordination.applyReconciliation(
                    rootPath: rootPath,
                    suggestedContent: reconciliation.suggestedContent
                )
                await reconcile(project: project)
            }
        } catch {
            statusByProject[project.identifier] = "Resolve failed: \(error.localizedDescription)"
        }
    }

    private static func statusText(for reconciliation: AgentNotesReconciliation) -> String {
        switch reconciliation.state {
        case .fileMissing: "AgentNotes.md is missing — generate to create it."
        case .fileMatches: "AgentNotes.md matches the SwiftData ledger."
        case .fileDiverged(let local, let generated):
            "Diverged: file \(local.prefix(8))… vs generated \(generated.prefix(8))…"
        case .conflictMarkers(let detail): detail
        }
    }
}

private struct AgentNotesProjectRow: View {
    let project: AgentProject
    let reconciliation: AgentNotesReconciliation?
    let mergeProposal: AgentNotesMergeProposal?
    let statusText: String?
    let mergeInProgress: Bool
    let eventCountForProject: Int
    let staleDispatchCount: Int
    let resolvingStaleDispatches: Bool
    let onReconcile: () async -> Void
    let onResolveStaleDispatches: () async -> Void
    let onApply: () -> Void
    let onProposeMerge: () async -> Void
    let onApplyMerge: () -> Void

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.headline)
                        Text(project.rootPath ?? "No local root path")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if let state = reconciliation?.state {
                        AgentNotesStateBadge(state: state)
                    }
                }

                if let statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await onReconcile() }
                    } label: {
                        Label("Reconcile", systemImage: "arrow.triangle.2.circlepath")
                    }
                    if staleDispatchCount > 0 {
                        Button {
                            Task { await onResolveStaleDispatches() }
                        } label: {
                            Label(
                                resolvingStaleDispatches ? "Resolving…" : "Resolve Stale Dispatches (\(staleDispatchCount))",
                                systemImage: "checkmark.circle"
                            )
                        }
                        .disabled(resolvingStaleDispatches)
                    }
                    if let reconciliation, reconciliation.requiresAttention {
                        Button {
                            onApply()
                        } label: {
                            Label("Regenerate from SwiftData", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let reconciliation, reconciliation.requiresAttention, reconciliation.onDiskContent != nil {
                        Button {
                            Task { await onProposeMerge() }
                        } label: {
                            Label(mergeInProgress ? "Proposing…" : "Propose Merge", systemImage: "sparkles")
                        }
                        .disabled(mergeInProgress)
                    }
                    Spacer()
                    Text("\(eventCountForProject) coordination events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let mergeProposal {
                    AgentNotesMergeProposalPreview(
                        proposal: mergeProposal,
                        onApply: onApplyMerge
                    )
                }
            }
        }
    }
}

private struct AgentNotesMergeProposalPreview: View {
    let proposal: AgentNotesMergeProposal
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Label("Merge proposal", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !proposal.unresolvedConflicts.isEmpty {
                    Label("\(proposal.unresolvedConflicts.count) conflict(s)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Text(proposal.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !proposal.unresolvedConflicts.isEmpty {
                ForEach(proposal.unresolvedConflicts, id: \.self) { conflict in
                    Label(conflict, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            ScrollView {
                Text(proposal.mergedContent)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .frame(maxHeight: 140)

            HStack {
                Text("\(proposal.retainedLocalLines.count) local / \(proposal.retainedGeneratedLines.count) generated retained")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onApply()
                } label: {
                    Label("Apply Merge", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!proposal.unresolvedConflicts.isEmpty)
            }
        }
    }
}

private struct AgentNotesStateBadge: View {
    let state: AgentNotesReconciliation.State

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 1))
            .foregroundStyle(tint)
    }

    private var label: String {
        switch state {
        case .fileMatches: "In sync"
        case .fileMissing: "Missing"
        case .fileDiverged: "Diverged"
        case .conflictMarkers: "Conflict"
        }
    }

    private var tint: Color {
        switch state {
        case .fileMatches: Color.green
        case .fileMissing: Color.orange
        case .fileDiverged: Color.accentColor
        case .conflictMarkers: Color.red
        }
    }
}

private struct KPIBlock: View {
    let title: String
    let value: String
    let detail: String

    private var tint: Color {
        AgenicTheme.accentColor(for: title)
    }

    var body: some View {
        GlassPanel {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title2.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.72), tint.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 11, height: 11)
                    .shadow(color: tint.opacity(0.28), radius: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HeatmapCell: View {
    let cell: DashboardHeatmapCell

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(cell.providerName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            HStack {
                Text(cell.metricName)
                Spacer()
                Text(cell.formattedValue)
                    .font(.caption.monospacedDigit())
            }
            .font(.caption)
        }
        .padding(10)
        .frame(minHeight: 74, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                        .fill(AgenicTheme.metricGradient(for: metricColor))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                .stroke(metricColor.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: metricColor.opacity(0.10), radius: 8, y: 3)
        .accessibilityLabel(cell.accessibilitySummary)
    }

    private var metricColor: Color {
        if cell.metricName == "Cost" {
            return cell.value < 0.3 ? .green : cell.value < 0.7 ? .orange : .red
        }
        return cell.value > 0.75 ? .green : cell.value > 0.45 ? .teal : .red
    }
}

private struct QuotaRow: View {
    let providerName: String
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(providerName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(refreshLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                if let pressure = snapshot.pressure {
                    GridRow {
                        quotaLabel("Calls")
                        ProgressView(value: clampToUnit(pressure.callsUsage))
                            .tint(barColor(for: pressure.callsUsage))
                        quotaDetail(callsDetail(pressure: pressure))
                    }
                    GridRow {
                        quotaLabel("Tokens")
                        ProgressView(value: clampToUnit(pressure.tokensUsage))
                            .tint(barColor(for: pressure.tokensUsage))
                        quotaDetail(tokensDetail(pressure: pressure))
                    }
                    GridRow {
                        quotaLabel("Cost")
                        ProgressView(value: clampToUnit(pressure.costUsage))
                            .tint(barColor(for: pressure.costUsage))
                        quotaDetail(costDetail(pressure: pressure))
                    }
                    GridRow {
                        quotaLabel("Session")
                        ProgressView(value: clampToUnit(pressure.sessionUsage))
                            .tint(barColor(for: pressure.sessionUsage))
                        quotaDetail(sessionDetail(pressure: pressure))
                    }
                } else {
                    GridRow {
                        quotaLabel("Aggregate")
                        ProgressView(value: clampToUnit(snapshot.limitPressure))
                            .tint(barColor(for: snapshot.limitPressure))
                        quotaDetail("Pressure \(snapshot.limitPressure.formatted(.percent.precision(.fractionLength(0))))")
                    }
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func quotaLabel(_ label: String) -> some View {
        Text(label)
            .frame(width: 64, alignment: .leading)
            .foregroundStyle(.secondary)
    }

    private func quotaDetail(_ detail: String) -> some View {
        Text(detail)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 150, alignment: .trailing)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func clampToUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func barColor(for usage: Double) -> Color {
        if usage >= 0.85 { return Color.red }
        if usage >= 0.6 { return Color.orange }
        return Color.accentColor
    }

    private var refreshLabel: String {
        guard let date = snapshot.refreshDate else { return "Manual reset" }
        return "Resets \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func callsDetail(pressure: UsagePressure) -> String {
        let cap = pressure.quota.maxCallsPerWindow
        return cap > 0 ? "\(snapshot.callsToday) / \(cap)" : "\(snapshot.callsToday)"
    }

    private func tokensDetail(pressure: UsagePressure) -> String {
        let cap = pressure.quota.maxTokensPerWindow
        if cap == 0 { return "Not tracked" }
        return "\(formatThousands(snapshot.tokenCountToday)) / \(formatThousands(cap))"
    }

    private func costDetail(pressure: UsagePressure) -> String {
        let cap = pressure.quota.softCostBudgetUSD
        let spent = snapshot.estimatedCostToday.formatted(.currency(code: "USD"))
        if cap == 0 { return "\(spent) (no budget)" }
        return "\(spent) / \(cap.formatted(.currency(code: "USD")))"
    }

    private func sessionDetail(pressure: UsagePressure) -> String {
        let used = formatHoursMinutes(snapshot.sessionSecondsToday)
        let cap = formatHoursMinutes(pressure.quota.maxSessionSecondsPerWindow)
        return "\(used) / \(cap)"
    }

    private func formatThousands(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0fk", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func formatHoursMinutes(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

private struct PerformanceTrendPanel: View {
    let summaries: [ProviderPerformanceSummary]

    private var allPoints: [ProviderPerformancePoint] {
        summaries.flatMap(\.trendline)
    }

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Model Performance Trend")
                    .font(.headline)
                Text("Per-provider accuracy across the most recent runs. Score contribution comes from the AccuracyRating attached to each RunOutcomeRecord — rate runs from the approval sheet to populate this view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Chart(allPoints) { point in
                    LineMark(
                        x: .value("Run", point.runIndex),
                        y: .value("Accuracy", point.accuracyScore)
                    )
                    .foregroundStyle(by: .value("Provider", point.providerName))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Run", point.runIndex),
                        y: .value("Accuracy", point.accuracyScore)
                    )
                    .foregroundStyle(by: .value("Provider", point.providerName))
                    .symbolSize(point.succeeded ? 36 : 18)
                }
                .chartYScale(domain: 0...1)
                .chartXAxisLabel("Run sequence (recent → older left→right)")
                .chartYAxisLabel("Accuracy contribution")
                .frame(minHeight: 200, idealHeight: 240)

                Divider()

                ForEach(summaries) { summary in
                    PerformanceSummaryRow(summary: summary)
                }
            }
        }
    }
}

private struct PerformanceSummaryRow: View {
    let summary: ProviderPerformanceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(summary.providerName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(summary.totalRuns) runs")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                Label(summary.successRate.formatted(.percent.precision(.fractionLength(0))), systemImage: "checkmark.seal")
                    .foregroundStyle(summary.successRate >= 0.8 ? Color.green : Color.orange)
                Label(summary.averageAccuracy.formatted(.percent.precision(.fractionLength(0))), systemImage: "scope")
                Label(formatLatency(summary.averageDurationSeconds), systemImage: "stopwatch")
                Label(summary.averageCostUSD.formatted(.currency(code: "USD")), systemImage: "creditcard")
                Spacer()
                if summary.cancelledCount > 0 {
                    Label("\(summary.cancelledCount) cancelled", systemImage: "xmark.circle")
                        .foregroundStyle(Color.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatLatency(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        if seconds >= 60 {
            let minutes = seconds / 60
            return String(format: "%.1f min", minutes)
        }
        return String(format: "%.1fs", seconds)
    }
}

private struct RouteScoreRow: View {
    let score: RoutingScoreBreakdown
    let tieBreak: RoutingTieBreak?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(score.providerName)
                            .font(.headline)
                        Spacer()
                        Text(score.totalScore.formatted(.percent.precision(.fractionLength(0))))
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }

                    ProgressView(value: score.totalScore)
                        .tint(isSelected ? Color.accentColor : Color.secondary)

                    Text(score.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)

                    if let tieBreak, score.providerID == tieBreak.selectedProviderID {
                        Label("On-device tie-break: \(tieBreak.reason)", systemImage: "sparkles")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .multilineTextAlignment(.leading)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            scoreMetaLabels
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            scoreMetaLabels
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var scoreMetaLabels: some View {
        Label(score.estimatedCostUSD.formatted(.currency(code: "USD")), systemImage: "creditcard")
        Label(score.limitImpact, systemImage: "gauge.with.dots.needle.bottom.50percent")
        Label(score.reliabilityImpact, systemImage: "waveform.path.ecg")
    }
}

private struct ProviderStatusBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.separator.opacity(0.35), lineWidth: 1))
    }
}

/// Sprint P.2: structured badge chip row showing the four Sprint P.2
/// status slots (binary / auth / credentials / freshness) with tone-driven
/// colors plus an accessibility summary for the worst slot.
private struct ProviderSetupBadgeStrip: View {
    let summary: ProviderSetupBadgeSummary

    var body: some View {
        HStack(spacing: 6) {
            ForEach(summary.badges) { badge in
                badgeChip(badge)
            }
        }
        .accessibilityLabel(summary.summary)
    }

    private func badgeChip(_ badge: ProviderSetupBadge) -> some View {
        HStack(spacing: 4) {
            Image(systemName: badge.tone.systemImage)
                .font(.caption2.weight(.semibold))
            Text(badge.label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(toneTextColor(badge.tone))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(toneBackground(badge.tone), in: Capsule())
        .overlay(Capsule().stroke(toneStroke(badge.tone), lineWidth: 1))
        .help(badge.detail + (badge.remediation.map { "\nRemediation: \($0)" } ?? ""))
        .accessibilityIdentifier("ProviderRow.\(badge.providerID).Badge.\(badge.kind.rawValue)")
    }

    private func toneBackground(_ tone: ProviderSetupBadgeTone) -> some ShapeStyle {
        switch tone {
        case .attention: AnyShapeStyle(Color.red.opacity(0.16))
        case .warning: AnyShapeStyle(Color.orange.opacity(0.18))
        case .neutral: AnyShapeStyle(Color.blue.opacity(0.14))
        case .healthy: AnyShapeStyle(Color.green.opacity(0.16))
        }
    }

    private func toneStroke(_ tone: ProviderSetupBadgeTone) -> Color {
        switch tone {
        case .attention: .red.opacity(0.45)
        case .warning: .orange.opacity(0.45)
        case .neutral: .blue.opacity(0.45)
        case .healthy: .green.opacity(0.40)
        }
    }

    private func toneTextColor(_ tone: ProviderSetupBadgeTone) -> Color {
        switch tone {
        case .attention: .red
        case .warning: .orange
        case .neutral: .blue
        case .healthy: .green
        }
    }
}

private struct CommandCopyView: View {
    let command: String

    var body: some View {
        HStack {
            Text(command)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy command")
        }
    }
}

private struct GlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                            .fill(AgenicTheme.glassTint)
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                            .stroke(.separator.opacity(0.24), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.13), radius: 16, y: 7)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AgenicDataModel.models, inMemory: true)
}
