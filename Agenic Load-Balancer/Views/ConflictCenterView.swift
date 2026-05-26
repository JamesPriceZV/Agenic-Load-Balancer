//
//  ConflictCenterView.swift
//  Agenic Load-Balancer
//
//  Sprint E: inspect operation-envelope conflicts before applying any
//  cross-machine resolution.
//

import SwiftData
import SwiftUI

struct ConflictCenterView: View {
    @Environment(\.modelContext) private var modelContext

    let conflicts: [ConflictResolutionRecord]
    let operations: [AutonomyOperationRecord]
    let peers: [MachinePeerRecord]
    let snapshots: [CloudSnapshotRecord]

    @State private var statusText = "Review divergent operation envelopes before resolving cross-machine state."

    private var previews: [ConflictResolutionPreview] {
        ConflictResolutionPreviewBuilder.build(
            records: conflicts,
            operations: operations,
            peers: peers,
            snapshots: snapshots
        )
    }

    private var openPreviews: [ConflictResolutionPreview] {
        previews.filter(\.isOpen)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                metrics

                if previews.isEmpty {
                    ContentUnavailableView(
                        "No conflicts detected",
                        systemImage: "checkmark.seal",
                        description: Text("Operation logs and conflict records do not currently require review.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ForEach(previews) { preview in
                        ConflictPreviewCard(
                            preview: preview,
                            onRecord: { action in
                                record(action: action, for: preview)
                            }
                        )
                    }
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Conflict Center")
                    .font(.largeTitle.weight(.semibold))
                Text(statusText)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(statusText)
                    .accessibilityValue(statusText)
                    .accessibilityIdentifier("Conflicts.Status")
            }
            Spacer(minLength: 16)
            Button {
                runRecoveryDrill()
            } label: {
                Label("Run Drill", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("Conflicts.RunDrillButton")
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            ConflictMetricTile(
                title: "Open",
                value: "\(openPreviews.count)",
                detail: "Needs review",
                systemImage: "exclamationmark.triangle",
                tint: openPreviews.isEmpty ? .green : .orange
            )
            ConflictMetricTile(
                title: "Operations",
                value: "\(operations.count)",
                detail: "Audited envelopes",
                systemImage: "list.bullet.rectangle.portrait",
                tint: .blue
            )
            ConflictMetricTile(
                title: "Peers",
                value: "\(peers.count)",
                detail: "Machine records",
                systemImage: "desktopcomputer",
                tint: .teal
            )
            ConflictMetricTile(
                title: "Snapshots",
                value: "\(snapshots.count)",
                detail: "Rollback anchors",
                systemImage: "camera.metering.matrix",
                tint: snapshots.isEmpty ? .orange : .green
            )
        }
    }

    private func record(action: ConflictResolutionAction, for preview: ConflictResolutionPreview) {
        let record = persistedRecord(for: preview)

        do {
            try ConflictResolutionPreviewBuilder.apply(action: action, to: record, using: preview)
            try modelContext.save()
            Task { await AppServices.cloudSync.recordLocalSave() }
            statusText = "\(action.label) recorded for \(preview.entityType) \(preview.entityID)."
        } catch {
            statusText = "Resolution failed: \(error.localizedDescription)"
        }
    }

    private func runRecoveryDrill() {
        do {
            let report = try ConflictRecoveryDrill.seedAndRun(in: modelContext)
            Task { await AppServices.cloudSync.recordLocalSave() }
            statusText = report.summary
        } catch {
            statusText = "Recovery drill failed: \(error.localizedDescription)"
        }
    }

    private func persistedRecord(for preview: ConflictResolutionPreview) -> ConflictResolutionRecord {
        if let recordID = preview.recordID,
           let record = conflicts.first(where: { $0.identifier == recordID }) {
            return record
        }

        let record = ConflictResolutionPreviewBuilder.makeRecord(from: preview)
        modelContext.insert(record)
        return record
    }
}

private struct ConflictMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius).stroke(.separator.opacity(0.28)))
    }
}

private struct ConflictPreviewCard: View {
    let preview: ConflictResolutionPreview
    let onRecord: (ConflictResolutionAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            inspector
            proposal
            warnings
            actions
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius).fill(AgenicTheme.glassTint))
        }
        .overlay(RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius).stroke(.separator.opacity(0.3)))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preview.entityType.capitalized)
                    .font(.headline)
                Text(preview.entityID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            ConflictStatusBadge(text: preview.status, tint: preview.isOpen ? .orange : .green)
        }
    }

    private var inspector: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("Conflict")
                    .foregroundStyle(.secondary)
                Text(preview.conflictKind)
                Text("Affected")
                    .foregroundStyle(.secondary)
                Text("\(preview.affectedEntityCount) entity / \(preview.affectedFieldCount) field(s)")
            }
            GridRow {
                Text("Local")
                    .foregroundStyle(.secondary)
                ConflictEnvelopeSummary(envelope: preview.local, createdAt: preview.localCreatedAt)
                Text("Remote")
                    .foregroundStyle(.secondary)
                ConflictEnvelopeSummary(envelope: preview.remote, createdAt: preview.remoteCreatedAt)
            }
            if preview.sourceRunID != nil || preview.sourceTaskID != nil || preview.sourcePlanID != nil {
                GridRow {
                    Text("Audit links")
                        .foregroundStyle(.secondary)
                    Text(auditLinks)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .gridCellColumns(3)
                }
            }
        }
        .font(.callout)
    }

    private var proposal: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Label("Dry-run preview", systemImage: "eye")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let action = preview.recommendedAction {
                    ConflictStatusBadge(text: "Recommended: \(action.label)", tint: .accentColor)
                }
            }
            Text(preview.outcomeSummary)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !preview.proposedPayload.isEmpty {
                ConflictPayloadGrid(payload: preview.proposedPayload)
            }

            if let snapshot = preview.restoreSnapshotID {
                Label("Rollback anchor: snapshot \(snapshot.prefix(8))", systemImage: "camera.metering.matrix")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var warnings: some View {
        if !preview.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(preview.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actionButtons }
            VStack(alignment: .leading, spacing: 8) { actionButtons }
        }
    }

    private var actionButtons: some View {
        ForEach(ConflictResolutionAction.allCases) { action in
            Button {
                onRecord(action)
            } label: {
                Label(action.label, systemImage: systemImage(for: action))
            }
            .disabled(!preview.isOpen || isDisabled(action))
            .help(action.detail)
            .accessibilityIdentifier("Conflicts.Action.\(action.rawValue).\(preview.entityID)")
        }
    }

    private var auditLinks: String {
        [
            preview.sourceRunID.map { "run=\($0)" },
            preview.sourceTaskID.map { "task=\($0)" },
            preview.sourcePlanID.map { "plan=\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func isDisabled(_ action: ConflictResolutionAction) -> Bool {
        if action.isRestoreLane {
            return preview.restoreSnapshotID == nil
        }
        if action == .merge {
            return preview.proposedPayload.isEmpty
        }
        return false
    }

    private func systemImage(for action: ConflictResolutionAction) -> String {
        switch action {
        case .keepLocal: "desktopcomputer"
        case .acceptRemote: "icloud.and.arrow.down"
        case .merge: "rectangle.2.swap"
        case .restoreSnapshot: "arrow.counterclockwise.circle"
        case .restoreIntoNewCopy: "square.stack.3d.up"
        }
    }
}

private struct ConflictEnvelopeSummary: View {
    let envelope: OperationEnvelope
    let createdAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(envelope.machineID)
                .lineLimit(1)
            Text("\(envelope.operationKind) · clock \(envelope.lamportClock)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ConflictPayloadGrid: View {
    let payload: [String: String]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(payload.keys.sorted(), id: \.self) { key in
                GridRow {
                    Text(key)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(payload[key] ?? "")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ConflictStatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.55), lineWidth: 1))
            .foregroundStyle(tint)
    }
}
