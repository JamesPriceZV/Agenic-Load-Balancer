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

    @State private var selectedSection: ConsoleSection? = .dashboard
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
                    sidebarItem(.history, "History", "clock.arrow.circlepath")
                }

                Section("Configure") {
                    sidebarItem(.providers, "Providers", "externaldrive.connected.to.line.below")
                    sidebarItem(.projects, "Projects", "folder.badge.gearshape")
                    sidebarItem(.restoreCenter, "Restore", "icloud.and.arrow.down")
                    sidebarItem(.agentNotes, "AgentNotes", "checklist")
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detailView
                .frame(minWidth: 940, minHeight: 660)
                .background(.background)
        }
        .task {
            AppBootstrapper.ensureSeedData(in: modelContext)
            await refreshCloudStatus()
            await observeRemoteCloudChanges()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    selectedSection = .promptRouter
                } label: {
                    Label("New Prompt", systemImage: "plus.message")
                }

                Button {
                    Task {
                        await refreshCloudStatus()
                    }
                } label: {
                    Label("Sync Status", systemImage: "arrow.triangle.2.circlepath.icloud")
                }
            }
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
        case .promptRouter:
            PromptRouterView(
                projects: projects,
                providers: providers,
                usageEntries: usageEntries,
                outcomes: outcomes,
                coordinationEvents: coordinationEvents
            )
        case .providers:
            ProviderSetupView(providers: providers)
        case .projects:
            ProjectsView(projects: projects, coordinationEvents: coordinationEvents)
        case .history:
            HistoryView(decisions: decisions, outcomes: outcomes, usageEntries: usageEntries)
        case .restoreCenter:
            RestoreCenterView(
                projects: projects,
                providers: providers,
                outcomes: outcomes,
                coordinationEvents: coordinationEvents,
                snapshots: snapshots,
                cloudStatus: cloudStatus
            )
        case .agentNotes:
            AgentNotesView(projects: projects, coordinationEvents: coordinationEvents)
        }
    }

    private func sidebarItem(_ section: ConsoleSection, _ label: String, _ systemImage: String) -> some View {
        NavigationLink(value: section) {
            Label(label, systemImage: systemImage)
        }
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

private enum ConsoleSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case promptRouter
    case providers
    case projects
    case history
    case restoreCenter
    case agentNotes

    var id: String { rawValue }
}

private struct DashboardView: View {
    let providers: [AgentProviderProfile]
    let usageEntries: [UsageLedgerEntry]
    let outcomes: [RunOutcomeRecord]
    let cloudStatus: CloudSyncStatusSnapshot

    private var usage: [UsageSnapshot] {
        UsageSnapshotBuilder.build(
            from: usageEntries,
            outcomes: outcomes,
            providers: providers
        )
    }

    private var accuracy: [AccuracySnapshot] {
        AccuracySnapshotBuilder.build(from: outcomes, providers: providers)
    }

    private var heatmapCells: [DashboardHeatmapCell] {
        DashboardMetricFactory.heatmapCells(providers: providers, usage: usage, accuracy: accuracy)
    }

    private var performanceSummaries: [ProviderPerformanceSummary] {
        PerformanceHistoryBuilder.build(
            providers: providers,
            outcomes: outcomes,
            usageEntries: usageEntries
        )
        .filter { $0.totalRuns > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                HStack(alignment: .top, spacing: 12) {
                    KPIBlock(title: "Providers", value: "\(providers.count)", detail: "\(availableProviderCount) locally available")
                    KPIBlock(title: "Runs", value: "\(outcomes.count)", detail: "\(ratedRunCount) rated for accuracy")
                    KPIBlock(title: "Estimated Cost", value: totalCost.formatted(.currency(code: "USD")), detail: "Observed today")
                    KPIBlock(title: "CloudKit", value: cloudStatus.status.capitalized, detail: cloudStatus.containerIdentifier)
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Model Use Heatmap")
                            .font(.headline)
                        Text("Six metrics per provider — availability, limit headroom, accuracy, latency, success rate, and observed cost — computed from SwiftData and syncable through private CloudKit metadata.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 110), spacing: 8), count: 6), spacing: 8) {
                            ForEach(heatmapCells) { cell in
                                HeatmapCell(cell: cell)
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
                                providerName: providers.first { $0.identifier == snapshot.providerID }?.displayName ?? snapshot.providerID,
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
                            let providerName = providers.first { $0.identifier == snapshot.providerID }?.displayName ?? snapshot.providerID
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
        providers.filter { $0.installedState == ProviderAvailabilityState.available.rawValue }.count
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

    let projects: [AgentProject]
    let providers: [AgentProviderProfile]
    let usageEntries: [UsageLedgerEntry]
    let outcomes: [RunOutcomeRecord]
    let coordinationEvents: [CoordinationEventRecord]

    @State private var prompt = ""
    @State private var selectedProjectID: String?
    @State private var selectedMode: AgentExecutionMode = .implementation
    @State private var scores: [RoutingScoreBreakdown] = []
    @State private var selectedScoreID: UUID?
    @State private var commandPreview = "Rank agents to preview the approved command."
    @State private var approvalStatus = ""
    @State private var dispatcher = RunDispatcher()
    @State private var isApprovalSheetPresented = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Prompt Router")
                    .font(.largeTitle.weight(.semibold))

                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker("Project", selection: $selectedProjectID) {
                                Text("No Project").tag(String?.none)
                                ForEach(projects, id: \.identifier) { project in
                                    Text(project.name).tag(Optional(project.identifier))
                                }
                            }
                            .frame(maxWidth: 360)

                            Picker("Mode", selection: $selectedMode) {
                                ForEach(AgentExecutionMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .frame(maxWidth: 260)
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

                        HStack {
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

                            Text(approvalStatus)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

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

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 560)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Routing Rationale")
                        .font(.title2.weight(.semibold))

                    if scores.isEmpty {
                        ContentUnavailableView(
                            "No routes ranked",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            description: Text("Enter a prompt and rank agents to see score breakdowns.")
                        )
                    } else {
                        ForEach(scores) { score in
                            RouteScoreRow(
                                score: score,
                                isSelected: selectedScoreID == score.id
                            ) {
                                selectedScoreID = score.id
                                buildCommandPreview(for: score)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 380, idealWidth: 460)
        }
        .sheet(isPresented: $isApprovalSheetPresented) {
            if let plan = currentRunPlan() {
                ApprovalSheetView(
                    plan: plan,
                    dispatcher: dispatcher,
                    onClose: {
                        isApprovalSheetPresented = false
                        approvalStatus = lastDispatcherStatusText()
                    }
                )
            } else {
                ContentUnavailableView(
                    "Select a route",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Rank agents and pick a route before reviewing.")
                )
                .frame(width: 480, height: 240)
            }
        }
    }

    private var selectedProject: AgentProject? {
        projects.first { $0.identifier == selectedProjectID }
    }

    private var selectedScore: RoutingScoreBreakdown? {
        scores.first { $0.id == selectedScoreID }
    }

    private func rankRoutes() {
        let providerSnapshots = providers.map { $0.snapshot() }
        let usage = UsageSnapshotBuilder.build(
            from: usageEntries,
            outcomes: outcomes,
            providers: providers
        )
        let accuracy = AccuracySnapshotBuilder.build(from: outcomes, providers: providers)
        let coordination = coordinationEvents.map { $0.snapshot() }
        let promptText = prompt
        let mode = selectedMode

        Task {
            let ranked = await AppServices.routingEngine.rank(
                prompt: promptText,
                mode: mode,
                providers: providerSnapshots,
                usage: usage,
                accuracy: accuracy,
                coordinationEvents: coordination
            )
            await MainActor.run {
                scores = ranked
                selectedScoreID = ranked.first?.id
                if let first = ranked.first {
                    buildCommandPreview(for: first)
                }
            }
        }
    }

    private func buildCommandPreview(for score: RoutingScoreBreakdown) {
        guard let provider = providers.first(where: { $0.identifier == score.providerID }) else {
            commandPreview = "Provider profile not found."
            return
        }

        do {
            let command = try AgentAdapterFactory
                .makeAdapter(providerID: score.providerID)
                .buildCommand(
                    prompt: prompt,
                    projectPath: selectedProject?.rootPath,
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
              let provider = providers.first(where: { $0.identifier == score.providerID }) else {
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
            mode: selectedMode,
            score: score,
            promptExcerptSyncEnabled: selectedProject?.promptExcerptSyncEnabled ?? false
        )
    }

    private func presentApprovalSheet() {
        guard currentRunPlan() != nil else { return }
        dispatcher.reset()
        isApprovalSheetPresented = true
    }

    private func lastDispatcherStatusText() -> String {
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

private struct ApprovalSheetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let plan: RunPlan
    let dispatcher: RunDispatcher
    let onClose: () -> Void

    @State private var elapsedSeconds: Double = 0
    @State private var preflightExcerpt: String?
    @State private var preflightLoaded: Bool = false

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
                        approvalSummary
                    } else {
                        runStatusBanner
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
        .task {
            await loadPreflightExcerpt()
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
            return
        }
        let excerpt = await AppServices.coordination.readAgentNotesExcerpt(rootPath: rootPath)
        preflightExcerpt = excerpt
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
                        Text(preflightExcerpt == nil ? "No AgentNotes.md found" : "Will be embedded in prompt")
                            .font(.caption)
                            .foregroundStyle(preflightExcerpt == nil ? Color.orange : Color.green)
                    } else {
                        Text("Loading…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("The agent receives the latest on-disk AgentNotes excerpt above your prompt so cross-agent claims are visible without a separate file read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let excerpt = preflightExcerpt, !excerpt.isEmpty {
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
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rate outcome")
                    .font(.headline)
                Text("Accuracy ratings feed the routing engine and dashboard heatmap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(AccuracyRating.allCases) { rating in
                        Button {
                            dispatcher.rateOutcome(rating, in: modelContext)
                        } label: {
                            Text(rating.rawValue)
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            switch dispatcher.status {
            case .idle:
                Button("Cancel", role: .cancel) { dismissSheet() }
                Button {
                    dispatcher.dispatch(
                        plan: plan,
                        agentNotesExcerpt: preflightExcerpt,
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
            case .succeeded, .failed, .cancelled:
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
        if dispatcher.status == .running || dispatcher.status == .preparing {
            dispatcher.cancel()
        }
        onClose()
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
                    projectPath: plan.projectRootPath,
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
        case .stderr: .red
        case .system: .accentColor
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .stdout: .primary
        case .stderr: .red
        case .system: .secondary
        }
    }
}

private struct WizardTarget: Identifiable {
    let id: String
    let provider: AgentProviderProfile
}

private struct ProviderSetupView: View {
    @Environment(\.modelContext) private var modelContext
    let providers: [AgentProviderProfile]

    @State private var isProbing = false
    @State private var statusText = "Installers are never run silently. Copy commands after reviewing the provider source."
    @State private var wizardTarget: WizardTarget?

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

                ForEach(providers, id: \.identifier) { provider in
                    ProviderProfileRow(provider: provider) {
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
                provider.installedState = health.availabilityState.rawValue
                provider.lastDetectedVersion = health.detectedVersion
                provider.lastHealthCheckAt = health.checkedAt
                provider.updatedAt = health.checkedAt
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
}

private struct ProviderProfileRow: View {
    let provider: AgentProviderProfile
    let onSetup: () -> Void

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

                    ProviderStatusBadge(title: provider.installedState)
                    ProviderStatusBadge(title: provider.authState)
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

                HStack {
                    Link("Provider Docs", destination: URL(string: provider.sourceURL) ?? URL(string: "https://example.com")!)
                    Spacer()
                    Button {
                        onSetup()
                    } label: {
                        Label("Set up…", systemImage: "wand.and.rays")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text(provider.safetyNotes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
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
                    Text(provider.authGuide)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Methods: \(provider.authMethods)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("API key")
                        .font(.headline)
                    Text("Stored only in the macOS Keychain (genericPassword). SwiftData/CloudKit hold a reference, never the secret.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Text("Browser sign-in (OAuth)")
                        .font(.headline)
                    Text("Opens an ASWebAuthenticationSession. Provide the provider's authorise URL and the URL scheme it redirects to.")
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
            probeStatus = health.message
            provider.installedState = health.availabilityState.rawValue
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

private struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    let projects: [AgentProject]
    let coordinationEvents: [CoordinationEventRecord]

    @State private var statusText = "Add local workspaces to enable AgentNotes coordination and per-project routing history."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Projects")
                            .font(.largeTitle.weight(.semibold))
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        addProject()
                    } label: {
                        Label("Add Workspace", systemImage: "folder.badge.plus")
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
                        GlassPanel {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(project.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(project.promptExcerptSyncEnabled ? "Prompt excerpts sync" : "Prompt excerpts local")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(project.rootPath ?? "No folder selected")
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                HStack {
                                    Button("Regenerate AgentNotes") {
                                        regenerateAgentNotes(for: project)
                                    }
                                    Toggle("Sync prompt excerpts", isOn: Binding(
                                        get: { project.promptExcerptSyncEnabled },
                                        set: { newValue in
                                            project.promptExcerptSyncEnabled = newValue
                                            project.updatedAt = Date()
                                            try? modelContext.save()
                                        }
                                    ))
                                    .toggleStyle(.switch)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
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
    let projects: [AgentProject]
    let coordinationEvents: [CoordinationEventRecord]

    @State private var reconciliations: [String: AgentNotesReconciliation] = [:]
    @State private var statusByProject: [String: String] = [:]
    @State private var pendingApply: PendingApply?

    private struct PendingApply: Identifiable {
        let id = UUID()
        let projectID: String
        let projectName: String
        let rootPath: String
        let suggestedContent: String
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
                        statusText: statusByProject[project.identifier],
                        eventCountForProject: coordinationEvents
                            .filter { $0.projectID == project.identifier || $0.projectID == nil }
                            .count,
                        onReconcile: {
                            await reconcile(project: project)
                        },
                        onApply: {
                            if let reconciliation = reconciliations[project.identifier] {
                                pendingApply = PendingApply(
                                    projectID: project.identifier,
                                    projectName: project.name,
                                    rootPath: project.rootPath ?? "",
                                    suggestedContent: reconciliation.suggestedContent
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
            "Replace AgentNotes.md with the regenerated version?",
            isPresented: Binding(
                get: { pendingApply != nil },
                set: { newValue in if !newValue { pendingApply = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) {
                if let target = pendingApply {
                    Task { await applyReconciliation(target: target) }
                }
            }
            Button("Cancel", role: .cancel) { pendingApply = nil }
        } message: {
            Text("This regenerates AgentNotes.md from the SwiftData coordination ledger. Hand-edits will be lost. The original is also a SwiftData record so nothing is permanently destroyed.")
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
        } catch {
            statusByProject[project.identifier] = "Reconcile failed: \(error.localizedDescription)"
        }
    }

    private func applyReconciliation(target: PendingApply) async {
        do {
            _ = try await AppServices.coordination.applyReconciliation(
                rootPath: target.rootPath,
                suggestedContent: target.suggestedContent
            )
            statusByProject[target.projectID] = "Regenerated AgentNotes.md from SwiftData."
            // Re-run the reconcile so the displayed state moves to fileMatches.
            if let project = projects.first(where: { $0.identifier == target.projectID }) {
                await reconcile(project: project)
            }
        } catch {
            statusByProject[target.projectID] = "Apply failed: \(error.localizedDescription)"
        }
        pendingApply = nil
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
    let statusText: String?
    let eventCountForProject: Int
    let onReconcile: () async -> Void
    let onApply: () -> Void

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
                    if let reconciliation, reconciliation.requiresAttention {
                        Button {
                            onApply()
                        } label: {
                            Label("Regenerate from SwiftData", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    Text("\(eventCountForProject) coordination events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .background(metricColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(metricColor.opacity(0.55), lineWidth: 1)
        )
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

                    HStack {
                        Label(score.estimatedCostUSD.formatted(.currency(code: "USD")), systemImage: "creditcard")
                        Label(score.limitImpact, systemImage: "gauge.with.dots.needle.bottom.50percent")
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.28), lineWidth: 1)
            )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AgenicDataModel.models, inMemory: true)
}
