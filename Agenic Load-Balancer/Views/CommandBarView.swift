//
//  CommandBarView.swift
//  Agenic Load-Balancer
//
//  Phase 7.3: natural-language command bar surface.
//

import SwiftData
import SwiftUI

struct CommandBarView: View {
    @Environment(\.dismiss) private var dismiss

    let projects: [AgentProject]
    let providers: [AgentProviderProfile]
    let usageEntries: [UsageLedgerEntry]
    let outcomes: [RunOutcomeRecord]
    let coordinationEvents: [CoordinationEventRecord]

    @State private var prompt = ""
    @State private var selectedProjectID: String?
    @State private var selectedMode: AgentExecutionMode = .implementation
    @State private var model = NaturalLanguageCommandBarModel()

    private let columns = [
        GridItem(.flexible(minimum: 150), spacing: 8),
        GridItem(.flexible(minimum: 150), spacing: 8),
        GridItem(.flexible(minimum: 150), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            quickActions
            resultPanel
            footer
        }
        .padding(18)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 520, idealHeight: 620)
        .background(.regularMaterial)
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.identifier
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "command")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Command Bar")
                    .font(.title2.weight(.semibold))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close command bar")
        }
    }

    private var controls: some View {
        CommandBarPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Picker("Project", selection: $selectedProjectID) {
                        Text("No Project").tag(String?.none)
                        ForEach(projects, id: \.identifier) { project in
                            Text(project.name).tag(Optional(project.identifier))
                        }
                    }
                    .frame(maxWidth: 320)

                    Picker("Mode", selection: $selectedMode) {
                        ForEach(AgentExecutionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .frame(maxWidth: 240)
                }

                HStack(alignment: .center, spacing: 8) {
                    TextField("Command", text: $prompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .onSubmit(submit)

                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Run command")
                    .disabled(model.state.isResponding || trimmedPrompt.isEmpty)
                }
            }
        }
    }

    private var quickActions: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(CommandBarQuickAction.allCases) { action in
                Button {
                    submit(action)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help(action.help)
                .disabled(model.state.isResponding)
            }
        }
    }

    private var resultPanel: some View {
        CommandBarPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Result")
                        .font(.headline)
                    Spacer()
                    statusPill
                }

                Divider()

                switch model.state {
                case .idle:
                    Text("Ready")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
                case .responding:
                    ProgressView("Thinking")
                        .frame(maxWidth: .infinity, minHeight: 250, alignment: .center)
                case .completed(let output):
                    ScrollView {
                        Text(output)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(minHeight: 250)
                case .failed(let reason):
                    Label(reason, systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Mutating actions stay draft-only until explicitly approved.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch model.state {
        case .idle:
            Label("Idle", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .responding:
            Label("Running", systemImage: "bolt.circle")
                .foregroundStyle(.blue)
        case .completed:
            Label("Complete", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "xmark.octagon")
                .foregroundStyle(.red)
        }
    }

    private var selectedProject: AgentProject? {
        projects.first { $0.identifier == selectedProjectID }
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var statusText: String {
        let projectName = selectedProject?.name ?? "No project"
        return "\(projectName) · \(selectedMode.label) · \(providers.count) provider(s)"
    }

    private func submit() {
        submit(commandText: trimmedPrompt)
    }

    private func submit(_ action: CommandBarQuickAction) {
        let command = action.command(basePrompt: trimmedPrompt, projectName: selectedProject?.name)
        prompt = command
        submit(commandText: command)
    }

    private func submit(commandText: String) {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.submit(prompt: trimmed, context: makeContext(prompt: trimmed))
    }

    private func makeContext(prompt: String) -> CommandBarContext {
        let usage = UsageSnapshotBuilder.build(
            from: usageEntries,
            outcomes: outcomes,
            providers: providers
        )
        let accuracy = AccuracySnapshotBuilder.build(from: outcomes, providers: providers)
        let reliability = ProviderReliabilityBuilder.build(providers: providers, outcomes: outcomes)
        return CommandBarContext(
            prompt: prompt,
            mode: selectedMode,
            projectID: selectedProject?.identifier,
            projectName: selectedProject?.name,
            projectRootPath: selectedProject?.rootPath,
            providers: providers.map { $0.snapshot() },
            usage: usage,
            accuracy: accuracy,
            reliability: reliability,
            coordinationEvents: coordinationEvents.map { $0.snapshot() }
        )
    }
}

private enum CommandBarQuickAction: String, CaseIterable, Identifiable {
    case rankAgents
    case dispatchRun
    case probeProviders
    case createSnapshot
    case reconcileAgentNotes
    case readDashboardMetrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rankAgents: return "Rank"
        case .dispatchRun: return "Dispatch"
        case .probeProviders: return "Probe"
        case .createSnapshot: return "Snapshot"
        case .reconcileAgentNotes: return "Reconcile"
        case .readDashboardMetrics: return "Metrics"
        }
    }

    var symbol: String {
        switch self {
        case .rankAgents: return "list.number"
        case .dispatchRun: return "paperplane"
        case .probeProviders: return "stethoscope"
        case .createSnapshot: return "archivebox"
        case .reconcileAgentNotes: return "arrow.triangle.2.circlepath"
        case .readDashboardMetrics: return "gauge.with.dots.needle.bottom.50percent"
        }
    }

    var help: String {
        switch self {
        case .rankAgents: return "Rank agents"
        case .dispatchRun: return "Prepare dispatch"
        case .probeProviders: return "Probe providers"
        case .createSnapshot: return "Prepare snapshot"
        case .reconcileAgentNotes: return "Reconcile AgentNotes"
        case .readDashboardMetrics: return "Read metrics"
        }
    }

    func command(basePrompt: String, projectName: String?) -> String {
        let target = projectName.map { " for \($0)" } ?? ""
        let suffix = basePrompt.isEmpty ? target : ": \(basePrompt)"
        switch self {
        case .rankAgents:
            return "rank agents\(suffix)"
        case .dispatchRun:
            return "dispatch a run\(suffix)"
        case .probeProviders:
            return "probe providers\(target)"
        case .createSnapshot:
            return "create a snapshot\(target)"
        case .reconcileAgentNotes:
            return "reconcile AgentNotes\(target)"
        case .readDashboardMetrics:
            return "read dashboard metrics\(target)"
        }
    }
}

private struct CommandBarPanel<Content: View>: View {
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
    CommandBarView(
        projects: [],
        providers: [],
        usageEntries: [],
        outcomes: [],
        coordinationEvents: []
    )
    .modelContainer(for: AgenicDataModel.models, inMemory: true)
}
