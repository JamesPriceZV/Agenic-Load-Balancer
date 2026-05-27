//
//  ConflictCenterView.swift
//  Agenic Load-Balancer
//
//  Sprint E: inspect operation-envelope conflicts before applying any
//  cross-machine resolution.
//
//  Sprint Q.4: wire the `.restoreIntoNewCopy` lane to the real
//  scoped-clone workflow and expose a Workspace Copies manager so
//  the user can archive or delete divergence workspaces.
//

import SwiftData
import SwiftUI

struct ConflictCenterView: View {
    @Environment(\.modelContext) private var modelContext

    let conflicts: [ConflictResolutionRecord]
    let operations: [AutonomyOperationRecord]
    let peers: [MachinePeerRecord]
    let snapshots: [CloudSnapshotRecord]
    var projects: [AgentProject] = []
    var tasks: [AutonomyTaskRecord] = []

    @State private var statusText = "Review divergent operation envelopes before resolving cross-machine state."
    @State private var pendingLargeCopy: PendingLargeCopy?

    private struct PendingLargeCopy: Identifiable {
        let id = UUID()
        let plan: RestoreIntoNewCopyPlan
        let record: ConflictResolutionRecord
        let preview: ConflictResolutionPreview
    }

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

    private var divergenceWorkspaces: [DivergenceWorkspaceSummary] {
        let allAudits = (try? modelContext.fetch(FetchDescriptor<AuditTrailRecord>())) ?? []
        return WorkspaceCopyManager.listDivergenceWorkspaces(
            projects: projects,
            tasks: tasks,
            audits: allAudits
        )
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

                if !divergenceWorkspaces.isEmpty {
                    workspaceCopiesSection
                }
            }
            .padding(24)
        }
        .confirmationDialog(
            largeCopyDialogTitle,
            isPresented: largeCopyPresented,
            presenting: pendingLargeCopy
        ) { pending in
            Button("Copy files anyway", role: .destructive) {
                applyRestorePlan(plan: pending.plan, record: pending.record, preview: pending.preview, allowLargeCopy: true)
                pendingLargeCopy = nil
            }
            Button("Skip file copy") {
                applyRestorePlan(plan: pending.plan, record: pending.record, preview: pending.preview, allowLargeCopy: false)
                pendingLargeCopy = nil
            }
            Button("Cancel", role: .cancel) {
                pendingLargeCopy = nil
            }
        } message: { pending in
            Text(largeCopyMessage(for: pending.plan))
        }
    }

    private var largeCopyDialogTitle: String {
        "Large workspace copy"
    }

    private var largeCopyPresented: Binding<Bool> {
        Binding(
            get: { pendingLargeCopy != nil },
            set: { presented in
                if !presented { pendingLargeCopy = nil }
            }
        )
    }

    private func largeCopyMessage(for plan: RestoreIntoNewCopyPlan) -> String {
        let size = RestoreIntoNewCopyMath.humanReadable(bytes: plan.estimatedSourceSizeBytes)
        let threshold = RestoreIntoNewCopyMath.humanReadable(bytes: plan.largeSizeThresholdBytes)
        return "The source workspace is approximately \(size) and exceeds the \(threshold) duplication threshold. Copying the files will create a complete sibling directory. SwiftData row clones run either way."
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

    @ViewBuilder
    private var workspaceCopiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Workspace Copies", systemImage: "square.stack.3d.up.fill")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(divergenceWorkspaces.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("Conflicts.WorkspaceCopies.Header")

            ForEach(divergenceWorkspaces) { workspace in
                DivergenceWorkspaceRow(
                    workspace: workspace,
                    onArchive: { archive(workspace: workspace) },
                    onDelete: { delete(workspace: workspace) }
                )
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius).fill(AgenicTheme.glassTint))
        }
        .overlay(RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius).stroke(.separator.opacity(0.3)))
    }

    private func record(action: ConflictResolutionAction, for preview: ConflictResolutionPreview) {
        let record = persistedRecord(for: preview)

        if action == .restoreIntoNewCopy {
            beginRestoreIntoNewCopy(preview: preview, record: record)
            return
        }

        do {
            try ConflictResolutionPreviewBuilder.apply(action: action, to: record, using: preview)
            try modelContext.save()
            Task { await AppServices.cloudSync.recordLocalSave() }
            statusText = "\(action.label) recorded for \(preview.entityType) \(preview.entityID)."
        } catch {
            statusText = "Resolution failed: \(error.localizedDescription)"
        }
    }

    private func beginRestoreIntoNewCopy(preview: ConflictResolutionPreview, record: ConflictResolutionRecord) {
        let allAudits = (try? modelContext.fetch(FetchDescriptor<AuditTrailRecord>())) ?? []
        let sourceProject = projects.first(where: { project in
            guard let projectID = tasks.first(where: { $0.identifier == preview.entityID })?.goalID else {
                return false
            }
            // Best-effort: match the goal back to a project via the goalID
            // stored on the autonomy goal record. The Conflict Center treats
            // the first matching project as the source.
            return project.identifier == projectID || project.name.contains(projectID.prefix(6))
        }) ?? projects.first

        let plan = RestoreIntoNewCopyPlanner.plan(
            for: preview,
            sourceProject: sourceProject,
            candidateTasks: tasks,
            candidateOperations: operations,
            candidateAudits: allAudits
        )

        if plan.requiresLargeSizeApproval {
            pendingLargeCopy = PendingLargeCopy(plan: plan, record: record, preview: preview)
            statusText = "Workspace at \(RestoreIntoNewCopyMath.humanReadable(bytes: plan.estimatedSourceSizeBytes)) exceeds duplication threshold. Confirm before copying files."
            return
        }

        applyRestorePlan(plan: plan, record: record, preview: preview, allowLargeCopy: false)
    }

    private func applyRestorePlan(
        plan: RestoreIntoNewCopyPlan,
        record: ConflictResolutionRecord,
        preview: ConflictResolutionPreview,
        allowLargeCopy: Bool
    ) {
        do {
            let result = try RestoreIntoNewCopyApplier.apply(
                plan: plan,
                allowLargeCopy: allowLargeCopy,
                modelContext: modelContext
            )
            try ConflictResolutionPreviewBuilder.apply(action: .restoreIntoNewCopy, to: record, using: preview)
            try modelContext.save()
            Task { await AppServices.cloudSync.recordLocalSave() }
            statusText = result.summary
        } catch {
            statusText = "Restore into new copy failed: \(error.localizedDescription)"
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

    private func archive(workspace: DivergenceWorkspaceSummary) {
        do {
            let archivedURL = try WorkspaceCopyManager.archive(workspace: workspace, modelContext: modelContext)
            Task { await AppServices.cloudSync.recordLocalSave() }
            if let url = archivedURL {
                statusText = "Archived \(workspace.name) to \(url.path)."
            } else {
                statusText = "Archived \(workspace.name); no filesystem copy was present."
            }
        } catch {
            statusText = "Archive failed: \(error.localizedDescription)"
        }
    }

    private func delete(workspace: DivergenceWorkspaceSummary) {
        do {
            try WorkspaceCopyManager.delete(workspace: workspace, modelContext: modelContext)
            Task { await AppServices.cloudSync.recordLocalSave() }
            statusText = "Deleted \(workspace.name) and its cloned rows."
        } catch {
            statusText = "Delete failed: \(error.localizedDescription)"
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

private struct DivergenceWorkspaceRow: View {
    let workspace: DivergenceWorkspaceSummary
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(workspace.name)
                    .font(.subheadline.weight(.semibold))
                if let conflictID = workspace.conflictID {
                    Text("Conflict \(conflictID.prefix(8))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let path = workspace.rootPath {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text("\(workspace.taskCount) task / \(workspace.auditCount) audit row(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ConflictStatusBadge(
                text: workspace.exists ? "on disk" : "no files",
                tint: workspace.exists ? .green : .orange
            )
            Button {
                onArchive()
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .help("Rename the sibling directory to __archived without deleting it.")
            .accessibilityIdentifier("Conflicts.WorkspaceCopies.Archive.\(workspace.id)")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Remove the sibling directory and the cloned SwiftData rows.")
            .accessibilityIdentifier("Conflicts.WorkspaceCopies.Delete.\(workspace.id)")
        }
        .padding(10)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
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
        if action == .restoreSnapshot {
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
