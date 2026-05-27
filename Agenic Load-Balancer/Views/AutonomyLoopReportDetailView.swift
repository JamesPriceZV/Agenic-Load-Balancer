//
//  AutonomyLoopReportDetailView.swift
//  Agenic Load-Balancer
//
//  Sprint Q.6: drill into a persisted `AutonomousLoopReportRecord`.
//  Lists every iteration with its status, detail, validation command,
//  exit code, and timestamp. Adds a filter toggle and a "Copy JSON"
//  button so the user can share the persisted report verbatim when
//  debugging a scheduler walk.
//

import AppKit
import SwiftUI

struct AutonomyLoopReportDetailView: View {
    let report: AutonomousLoopReportRecord
    var onClose: () -> Void = {}

    @State private var filter: AutonomyLoopReportFilter = .all
    @State private var copyConfirmation: String?

    private var iterations: [AutonomousLoopIteration] {
        AutonomousLoopPersistence.decodeIterations(report.iterationsJSON)
    }

    private var filteredIterations: [AutonomousLoopIteration] {
        filter.apply(to: iterations)
    }

    private var completedTaskIDs: [String] {
        AutonomousLoopPersistence.decodeTaskIDs(report.completedTaskIDsJSON)
    }

    private var pendingTaskIDs: [String] {
        AutonomousLoopPersistence.decodeTaskIDs(report.pendingTaskIDsJSON)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            filterBar
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if filteredIterations.isEmpty {
                        ContentUnavailableView(
                            "No matching iterations",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Switch filter to see other iterations from this run.")
                        )
                        .padding(.vertical, 40)
                    } else {
                        ForEach(filteredIterations) { iteration in
                            AutonomyLoopIterationCard(iteration: iteration)
                        }
                    }
                    taskRollup
                }
                .padding(20)
            }
            footer
        }
        .frame(minWidth: 560, idealWidth: 720, minHeight: 460, idealHeight: 620)
        .accessibilityIdentifier("Autonomy.LoopReportDetail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loop Report")
                        .font(.title2.weight(.semibold))
                    Text("Plan \(report.planID)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("Autonomy.LoopReportDetail.Close")
            }
            HStack(spacing: 10) {
                haltReasonChip
                counterPill(label: "Iterations", value: iterations.count, tint: .blue)
                counterPill(label: "Failures", value: report.validationFailureCount, tint: report.validationFailureCount > 0 ? .red : .secondary)
                counterPill(label: "Approvals", value: report.approvalSurfaceCount, tint: report.approvalSurfaceCount > 0 ? .blue : .secondary)
            }
            HStack(spacing: 12) {
                Label(report.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "play.circle")
                Label(report.endedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "stop.circle")
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(report.haltReasonLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial)
    }

    private var haltReasonChip: some View {
        Text(haltReasonChipLabel)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(haltReasonTint.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(haltReasonTint.opacity(0.6), lineWidth: 1))
            .foregroundStyle(haltReasonTint)
            .accessibilityIdentifier("Autonomy.LoopReportDetail.Chip")
    }

    private var haltReasonTint: Color {
        switch report.haltReasonKind {
        case "completed": .green
        case "approvalRequired", "approvalCap": .blue
        case "denied", "validationFailureCap", "dependencyDeadlock": .red
        case "iterationCap": .orange
        default: .secondary
        }
    }

    private var haltReasonChipLabel: String {
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

    private func counterPill(label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
            Text("\(value)")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
        .foregroundStyle(tint)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Text("Filter")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Filter", selection: $filter) {
                ForEach(AutonomyLoopReportFilter.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("Autonomy.LoopReportDetail.Filter")
            Spacer()
            Text("\(filteredIterations.count) of \(iterations.count)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var taskRollup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Task Roll-up")
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .top, spacing: 16) {
                taskColumn(title: "Completed", ids: completedTaskIDs, tint: .green)
                taskColumn(title: "Pending", ids: pendingTaskIDs, tint: .orange)
            }
        }
    }

    private func taskColumn(title: String, ids: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text("\(ids.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if ids.isEmpty {
                Text("None")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ids, id: \.self) { id in
                    Text(id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            if let copyConfirmation {
                Label(copyConfirmation, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Spacer()
            }
            Spacer()
            Button {
                copyReportJSON()
            } label: {
                Label("Copy JSON", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("Autonomy.LoopReportDetail.CopyJSON")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func copyReportJSON() {
        let json = AutonomyLoopReportJSON.encode(report)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        copyConfirmation = "Copied \(json.count) chars to clipboard"
    }
}

private struct AutonomyLoopIterationCard: View {
    let iteration: AutonomousLoopIteration

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(iteration.index)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(iteration.taskTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                statusBadge
            }
            Text(iteration.taskID)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(iteration.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let command = iteration.validationCommand, !command.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .foregroundStyle(.secondary)
                    Text(command)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer()
                    if let exit = iteration.validationExitCode {
                        Text("exit \(exit)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(exit == 0 ? .green : .red)
                    }
                }
            }
            HStack(spacing: 8) {
                Label(iteration.mode, systemImage: "gearshape.2")
                Spacer()
                Text(iteration.occurredAt.formatted(date: .omitted, time: .standard))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("Autonomy.LoopReportDetail.Iteration.\(iteration.index)")
    }

    private var statusBadge: some View {
        let (label, tint) = badgeAttributes
        return Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 1))
            .foregroundStyle(tint)
    }

    private var badgeAttributes: (String, Color) {
        switch iteration.status {
        case .completedAdvisory: ("Advisory", .teal)
        case .validationPassed: ("Validated", .green)
        case .validationFailed: ("Failed", .red)
        case .approvalRequired: ("Approval", .blue)
        case .denied: ("Denied", .red)
        case .dependenciesUnresolved: ("Blocked", .orange)
        }
    }
}

/// Pure encoder used by the detail view's "Copy JSON" button and by
/// regression tests. Keeps the JSON shape stable so users can paste
/// the output into bug reports or test fixtures.
enum AutonomyLoopReportJSON {
    static func encode(_ report: AutonomousLoopReportRecord) -> String {
        var dict: [String: Any] = [:]
        dict["identifier"] = report.identifier
        dict["goalID"] = report.goalID
        dict["planID"] = report.planID
        dict["haltReasonKind"] = report.haltReasonKind
        dict["haltReasonLabel"] = report.haltReasonLabel
        dict["validationFailureCount"] = report.validationFailureCount
        dict["approvalSurfaceCount"] = report.approvalSurfaceCount
        dict["startedAt"] = ISO8601DateFormatter().string(from: report.startedAt)
        dict["endedAt"] = ISO8601DateFormatter().string(from: report.endedAt)
        dict["completedTaskIDs"] = AutonomousLoopPersistence.decodeTaskIDs(report.completedTaskIDsJSON)
        dict["pendingTaskIDs"] = AutonomousLoopPersistence.decodeTaskIDs(report.pendingTaskIDsJSON)
        dict["iterations"] = iterationsAsAny(report.iterationsJSON)
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .prettyPrinted]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }

    private static func iterationsAsAny(_ json: String) -> [[String: Any]] {
        AutonomousLoopPersistence.decodeIterations(json).map { iteration in
            var entry: [String: Any] = [
                "index": iteration.index,
                "taskID": iteration.taskID,
                "taskTitle": iteration.taskTitle,
                "mode": iteration.mode,
                "status": iteration.status.rawValue,
                "detail": iteration.detail,
                "occurredAt": ISO8601DateFormatter().string(from: iteration.occurredAt),
            ]
            if let command = iteration.validationCommand {
                entry["validationCommand"] = command
            }
            if let exit = iteration.validationExitCode {
                entry["validationExitCode"] = exit
            }
            return entry
        }
    }
}
