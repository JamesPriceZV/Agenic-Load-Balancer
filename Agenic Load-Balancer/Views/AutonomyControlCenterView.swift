//
//  AutonomyControlCenterView.swift
//  Agenic Load-Balancer
//
//  Phase 7.6: safe goal intake and autonomous plan drafting.
//

import Foundation
import SwiftUI

struct AutonomyControlCenterView: View {
    let projects: [AgentProject]
    let draftPlan: @Sendable (AutonomousGoalRequest) async throws -> AutonomousPlanDraft

    @State private var selectedProjectID: String?
    @State private var goalTitle = ""
    @State private var goalDescription = ""
    @State private var level: AutonomyLevel = .proposeActions
    @State private var draft: AutonomousPlanDraft?
    @State private var statusText = ""
    @State private var isDrafting = false

    private var selectedProject: AgentProject? {
        selectedProjectID.flatMap { id in projects.first { $0.identifier == id } } ?? projects.first
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
                Label(isDrafting ? "Drafting" : "Draft Plan", systemImage: "list.bullet.clipboard")
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
        }
        .padding(12)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
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

        var policy = AutonomyPolicy.defaultSafe
        policy.level = level
        if let rootPath = selectedProject?.rootPath {
            policy.allowedRootPaths = [rootPath]
        }

        let request = AutonomousGoalRequest(
            title: goalTitle,
            goalDescription: goalDescription,
            projectID: selectedProject?.identifier,
            projectRootPath: selectedProject?.rootPath,
            autonomyPolicy: policy
        )

        do {
            draft = try await draftPlan(request)
            statusText = "Draft ready."
        } catch {
            draft = nil
            statusText = error.localizedDescription
        }
    }

    private func evaluate(_ task: AutonomousTaskDraft) -> AutonomyPolicyDecision {
        var policy = AutonomyPolicy.defaultSafe
        policy.level = level
        if let rootPath = selectedProject?.rootPath {
            policy.allowedRootPaths = [rootPath]
        }
        return AutonomyPolicyEvaluator().evaluateRun(
            mode: task.mode,
            estimatedCostUSD: 0.01,
            policy: policy
        )
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
