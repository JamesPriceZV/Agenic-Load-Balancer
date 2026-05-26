//
//  RestoreIntoNewCopyWorkflow.swift
//  Agenic Load-Balancer
//
//  Sprint Q.4: turn the Conflict Center's `.restoreIntoNewCopy` lane
//  from a planning placeholder into an actual scoped clone.
//
//  Workflow stages:
//
//   1. `RestoreIntoNewCopyPlanner.plan(...)` — pure function over a
//      `ConflictResolutionPreview` plus pre-fetched SwiftData rows.
//      Decides what the new copy will contain, estimates filesystem
//      size, and decides whether the size warrants explicit approval.
//      Never mutates SwiftData or the filesystem.
//   2. `RestoreIntoNewCopyApplier.apply(...)` — inserts the cloned
//      SwiftData rows (new AgentProject, cloned task, cloned audit
//      entries, cloned operation envelopes), creates the sibling
//      directory under the original project root's parent, recursively
//      copies workspace files (skipping known-large/derived caches),
//      writes `DIVERGENCE.md`, an isolated `AgentNotes.md` divergence
//      note, and a `cloned-rows.json` row dump.
//   3. `WorkspaceCopyManager` — list/archive/delete utility for
//      divergence workspaces created by this workflow, so the user can
//      clean up sibling clones without manually editing SwiftData.
//
//  Safety contract:
//   - Source rows are never mutated. The cloned `AgentProject`,
//     `AutonomyTaskRecord`, `AutonomyOperationRecord`, and
//     `AuditTrailRecord` rows live alongside the originals with
//     scoped identifiers (`restore::<conflictID>::...`).
//   - Filesystem writes are confined to a single sibling directory
//     under the parent of the original project root, named
//     `<originalRootName>__divergence-<shortConflictID>`.
//   - If the planner estimates the workspace at or above the large-
//     size threshold, the applier refuses to copy files unless the
//     caller explicitly opts in by setting `allowLargeCopy=true`.
//   - Read-only when no project root is configured: the SwiftData
//     row clone still happens; the filesystem stage is skipped.
//

import Foundation
import SwiftData

// MARK: - Plan / Result Types

struct ClonedTaskRowPlan: Sendable, Hashable {
    let sourceTaskID: String
    let clonedTaskID: String
    let goalID: String?
    let parentTaskID: String?
    let title: String
    let detail: String
    let status: String
    let mode: String
    let assignedProviderID: String?
    let dependencyIDsJSON: String
    let validationCommand: String?
}

struct ClonedOperationRowPlan: Sendable, Hashable {
    let sourceOperationID: String
    let clonedOperationID: String
    let entityID: String
    let entityType: String
    let operationKind: String
    let lamportClock: Int
    let machineID: String
    let payloadJSON: String
}

struct ClonedAuditRowPlan: Sendable, Hashable {
    let sourceAuditID: String
    let clonedAuditID: String
    let goalID: String?
    let taskID: String?
    let eventKind: String
    let detail: String
}

struct ClonedProjectRowPlan: Sendable, Hashable {
    let sourceProjectID: String?
    let clonedProjectID: String
    let clonedName: String
    let clonedRootPath: String?
    let clonedAgentNotesRelativePath: String
}

struct RestoreIntoNewCopyPlan: Sendable, Hashable {
    let conflictID: String
    let entityID: String
    let entityType: String
    let sourceProjectID: String?
    let sourceProjectName: String?
    let sourceRootPath: String?
    let siblingDirectoryURL: URL?
    let projectClone: ClonedProjectRowPlan?
    let taskClones: [ClonedTaskRowPlan]
    let operationClones: [ClonedOperationRowPlan]
    let auditClones: [ClonedAuditRowPlan]
    let estimatedSourceSizeBytes: Int64
    let largeSizeThresholdBytes: Int64
    let agentNotesDivergenceNote: String
    let createdAt: Date

    /// True when the workspace exceeds the configured threshold and the
    /// caller must opt into copying the files. The SwiftData row clone
    /// always proceeds.
    var requiresLargeSizeApproval: Bool {
        siblingDirectoryURL != nil && estimatedSourceSizeBytes >= largeSizeThresholdBytes
    }

    /// Short, stable identifier suffix shared by every cloned row so the
    /// workspace manager can scope its actions.
    var lineageSuffix: String {
        "restore::\(conflictID)"
    }
}

struct RestoreIntoNewCopyResult: Sendable, Hashable {
    enum FilesystemOutcome: String, Sendable, Hashable {
        case notAttempted
        case copied
        case skippedLargeSize
        case skippedMissingRoot
    }

    let plan: RestoreIntoNewCopyPlan
    let createdProjectID: String?
    let createdTaskIDs: [String]
    let createdOperationIDs: [String]
    let createdAuditIDs: [String]
    let siblingDirectoryURL: URL?
    let filesystemOutcome: FilesystemOutcome
    let bytesCopied: Int64
    let summary: String
}

enum RestoreIntoNewCopyError: Error, CustomStringConvertible, Sendable {
    case requiresLargeSizeApproval(bytes: Int64)
    case siblingDirectoryAlreadyExists(URL)
    case fileCopyFailed(URL, String)
    case directoryCreationFailed(URL, String)

    var description: String {
        switch self {
        case .requiresLargeSizeApproval(let bytes):
            return "Workspace copy is ~\(RestoreIntoNewCopyMath.humanReadable(bytes: bytes)); large-size approval required before files are duplicated."
        case .siblingDirectoryAlreadyExists(let url):
            return "Sibling directory already exists at \(url.path)."
        case .fileCopyFailed(let url, let reason):
            return "Failed to copy \(url.path): \(reason)"
        case .directoryCreationFailed(let url, let reason):
            return "Failed to create directory \(url.path): \(reason)"
        }
    }
}

// MARK: - Planner

enum RestoreIntoNewCopyPlanner {
    /// Default ~100 MB. Anything at or above this triggers an explicit
    /// confirmation requirement in the UI before files are copied.
    static let defaultLargeSizeThresholdBytes: Int64 = 100 * 1024 * 1024

    /// Excluded path components that should never be copied during a
    /// divergence clone. These tend to be huge, regeneratable, or
    /// machine-specific build/runtime caches.
    static let excludedPathComponents: Set<String> = [
        ".git",
        ".svn",
        ".hg",
        "node_modules",
        "DerivedData",
        "Build",
        "build",
        ".build",
        ".next",
        ".cache",
        "Pods",
        "Carthage",
        ".venv",
        "venv",
        ".tox",
        "target",
        "dist",
        "out",
        ".idea",
        ".vscode/.history",
        "__pycache__",
    ]

    static func plan(
        for preview: ConflictResolutionPreview,
        sourceProject: AgentProject?,
        candidateTasks: [AutonomyTaskRecord],
        candidateOperations: [AutonomyOperationRecord],
        candidateAudits: [AuditTrailRecord],
        largeSizeThresholdBytes: Int64 = RestoreIntoNewCopyPlanner.defaultLargeSizeThresholdBytes,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> RestoreIntoNewCopyPlan {
        let conflictID = preview.recordID ?? preview.id
        let shortConflictID = String(conflictID.prefix(8))
        let entityID = preview.entityID

        let sourceTask = candidateTasks.first(where: { $0.identifier == entityID })
        var taskClones: [ClonedTaskRowPlan] = []
        if let task = sourceTask {
            taskClones.append(
                ClonedTaskRowPlan(
                    sourceTaskID: task.identifier,
                    clonedTaskID: clonedID(kind: "task", conflictID: conflictID),
                    goalID: task.goalID,
                    parentTaskID: task.parentTaskID,
                    title: "\(task.title) (divergence \(shortConflictID))",
                    detail: divergenceDetailPrefix(conflictID: conflictID) + task.detail,
                    status: task.status,
                    mode: task.mode,
                    assignedProviderID: task.assignedProviderID,
                    dependencyIDsJSON: task.dependencyIDsJSON,
                    validationCommand: task.validationCommand
                )
            )
        }

        let scopedOperations = candidateOperations.filter { $0.entityID == entityID }
        let operationClones = scopedOperations.map { op in
            ClonedOperationRowPlan(
                sourceOperationID: op.identifier,
                clonedOperationID: clonedID(kind: "op", conflictID: conflictID),
                entityID: op.entityID,
                entityType: op.entityType,
                operationKind: op.operationKind,
                lamportClock: op.lamportClock,
                machineID: op.machineID,
                payloadJSON: op.payloadJSON
            )
        }

        let scopedAudits = candidateAudits.filter { audit in
            audit.taskID == entityID ||
                (sourceTask != nil && audit.goalID == sourceTask?.goalID)
        }
        let auditClones = scopedAudits.map { audit in
            ClonedAuditRowPlan(
                sourceAuditID: audit.identifier,
                clonedAuditID: clonedID(kind: "audit", conflictID: conflictID),
                goalID: audit.goalID,
                taskID: audit.taskID,
                eventKind: audit.eventKind,
                detail: audit.detail
            )
        }

        var projectClone: ClonedProjectRowPlan?
        var siblingURL: URL?
        var estimatedSize: Int64 = 0

        if let project = sourceProject {
            let sourceRoot = project.rootPath.flatMap { path -> URL? in
                let url = URL(fileURLWithPath: path, isDirectory: true)
                return fileManager.fileExists(atPath: url.path) ? url : nil
            }

            let siblingDirectory = sourceRoot.flatMap { root -> URL? in
                let parent = root.deletingLastPathComponent()
                guard fileManager.fileExists(atPath: parent.path) else { return nil }
                let name = "\(root.lastPathComponent)__divergence-\(shortConflictID)"
                return parent.appendingPathComponent(name, isDirectory: true)
            }

            siblingURL = siblingDirectory
            estimatedSize = sourceRoot.map { estimateDirectorySize(at: $0, fileManager: fileManager) } ?? 0

            projectClone = ClonedProjectRowPlan(
                sourceProjectID: project.identifier,
                clonedProjectID: clonedID(kind: "project", conflictID: conflictID),
                clonedName: "\(project.name) (divergence \(shortConflictID))",
                clonedRootPath: siblingDirectory?.path,
                clonedAgentNotesRelativePath: project.agentNotesRelativePath
            )
        }

        let note = renderDivergenceNote(
            preview: preview,
            sourceProject: sourceProject,
            taskClones: taskClones,
            operationClones: operationClones,
            auditClones: auditClones,
            siblingDirectoryURL: siblingURL,
            now: now
        )

        return RestoreIntoNewCopyPlan(
            conflictID: conflictID,
            entityID: entityID,
            entityType: preview.entityType,
            sourceProjectID: sourceProject?.identifier,
            sourceProjectName: sourceProject?.name,
            sourceRootPath: sourceProject?.rootPath,
            siblingDirectoryURL: siblingURL,
            projectClone: projectClone,
            taskClones: taskClones,
            operationClones: operationClones,
            auditClones: auditClones,
            estimatedSourceSizeBytes: estimatedSize,
            largeSizeThresholdBytes: largeSizeThresholdBytes,
            agentNotesDivergenceNote: note,
            createdAt: now
        )
    }

    private static func clonedID(kind: String, conflictID: String) -> String {
        "restore::\(conflictID)::\(kind)::\(UUID().uuidString)"
    }

    private static func divergenceDetailPrefix(conflictID: String) -> String {
        "[Divergence \(conflictID.prefix(8))] "
    }

    private static func estimateDirectorySize(at url: URL, fileManager: FileManager) -> Int64 {
        var total: Int64 = 0
        let resourceKeys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }
        for case let fileURL as URL in enumerator {
            let pathComponents = Set(fileURL.pathComponents)
            if !excludedPathComponents.isDisjoint(with: pathComponents) {
                enumerator.skipDescendants()
                continue
            }
            if let values = try? fileURL.resourceValues(forKeys: resourceKeys) {
                if values.isDirectory == true { continue }
                if let bytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                    total &+= Int64(bytes)
                }
            }
        }
        return total
    }

    private static func renderDivergenceNote(
        preview: ConflictResolutionPreview,
        sourceProject: AgentProject?,
        taskClones: [ClonedTaskRowPlan],
        operationClones: [ClonedOperationRowPlan],
        auditClones: [ClonedAuditRowPlan],
        siblingDirectoryURL: URL?,
        now: Date
    ) -> String {
        var lines: [String] = []
        lines.append("# Divergence Note")
        lines.append("")
        lines.append("- Conflict: `\(preview.recordID ?? preview.id)`")
        lines.append("- Entity: `\(preview.entityType)` / `\(preview.entityID)`")
        lines.append("- Conflict kind: `\(preview.conflictKind)`")
        lines.append("- Captured at: \(ISO8601DateFormatter().string(from: now))")
        if let source = sourceProject {
            lines.append("- Source project: \(source.name) (`\(source.identifier)`)")
            if let root = source.rootPath {
                lines.append("- Source root: `\(root)`")
            }
        }
        if let sibling = siblingDirectoryURL {
            lines.append("- Sibling copy: `\(sibling.path)`")
        }
        lines.append("")
        lines.append("## Local Operation")
        lines.append("- Machine: `\(preview.local.machineID)`")
        lines.append("- Clock: \(preview.local.lamportClock)")
        lines.append("- Captured at: \(ISO8601DateFormatter().string(from: preview.localCreatedAt))")
        lines.append("")
        lines.append("## Remote Operation")
        lines.append("- Machine: `\(preview.remote.machineID)`")
        lines.append("- Clock: \(preview.remote.lamportClock)")
        lines.append("- Captured at: \(ISO8601DateFormatter().string(from: preview.remoteCreatedAt))")
        lines.append("")
        lines.append("## Outcome Summary")
        lines.append(preview.outcomeSummary)
        lines.append("")
        lines.append("## Cloned Rows")
        lines.append("- \(taskClones.count) autonomy task(s)")
        lines.append("- \(operationClones.count) operation envelope(s)")
        lines.append("- \(auditClones.count) audit trail entry(ies)")
        lines.append("")
        lines.append("Original rows are untouched. The cloned rows carry a `restore::\(preview.recordID ?? preview.id)` lineage prefix on their identifiers.")
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Applier

@MainActor
enum RestoreIntoNewCopyApplier {
    static func apply(
        plan: RestoreIntoNewCopyPlan,
        allowLargeCopy: Bool = false,
        modelContext: ModelContext,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> RestoreIntoNewCopyResult {
        var createdTaskIDs: [String] = []
        var createdOperationIDs: [String] = []
        var createdAuditIDs: [String] = []
        var createdProjectID: String?

        // 1. Clone project row if the source has one.
        if let projectPlan = plan.projectClone {
            let project = AgentProject(
                identifier: projectPlan.clonedProjectID,
                name: projectPlan.clonedName,
                rootPath: projectPlan.clonedRootPath,
                agentNotesRelativePath: projectPlan.clonedAgentNotesRelativePath,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(project)
            createdProjectID = project.identifier
        }

        // 2. Clone autonomy task rows.
        for clone in plan.taskClones {
            let task = AutonomyTaskRecord(
                identifier: clone.clonedTaskID,
                goalID: clone.goalID,
                parentTaskID: clone.parentTaskID,
                title: clone.title,
                detail: clone.detail,
                status: clone.status,
                mode: clone.mode,
                assignedProviderID: clone.assignedProviderID,
                dependencyIDsJSON: clone.dependencyIDsJSON,
                validationCommand: clone.validationCommand,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(task)
            createdTaskIDs.append(task.identifier)
        }

        // 3. Clone operation envelopes.
        for clone in plan.operationClones {
            let op = AutonomyOperationRecord(
                identifier: clone.clonedOperationID,
                entityID: plan.taskClones.first(where: { $0.sourceTaskID == clone.entityID })?.clonedTaskID ?? clone.entityID,
                entityType: clone.entityType,
                operationKind: clone.operationKind,
                lamportClock: clone.lamportClock,
                machineID: clone.machineID,
                payloadJSON: clone.payloadJSON,
                createdAt: now
            )
            modelContext.insert(op)
            createdOperationIDs.append(op.identifier)
        }

        // 4. Clone audit rows + write an audit entry per source row so the
        //    history view can rebuild the divergence trail.
        for clone in plan.auditClones {
            let audit = AuditTrailRecord(
                identifier: clone.clonedAuditID,
                goalID: clone.goalID,
                taskID: plan.taskClones.first(where: { $0.sourceTaskID == clone.taskID })?.clonedTaskID ?? clone.taskID,
                eventKind: clone.eventKind,
                detail: clone.detail,
                createdAt: now
            )
            modelContext.insert(audit)
            createdAuditIDs.append(audit.identifier)
        }

        // Always append a single high-level audit entry describing the divergence.
        let divergenceAudit = AuditTrailRecord(
            goalID: plan.taskClones.first?.goalID,
            taskID: plan.taskClones.first?.clonedTaskID,
            eventKind: "conflict.restoreIntoNewCopy.applied",
            detail: "Cloned \(plan.taskClones.count) task / \(plan.operationClones.count) op / \(plan.auditClones.count) audit rows for conflict \(plan.conflictID).",
            createdAt: now
        )
        modelContext.insert(divergenceAudit)
        createdAuditIDs.append(divergenceAudit.identifier)

        // 5. Filesystem stage.
        var filesystemOutcome: RestoreIntoNewCopyResult.FilesystemOutcome = .notAttempted
        var bytesCopied: Int64 = 0
        var actualSiblingURL: URL?

        if let siblingURL = plan.siblingDirectoryURL,
           let sourceRoot = plan.sourceRootPath {
            if plan.requiresLargeSizeApproval && !allowLargeCopy {
                filesystemOutcome = .skippedLargeSize
                // The applier intentionally still creates the sibling directory
                // and the divergence note even when the file copy is skipped —
                // that way the user has somewhere to land on disk.
                do {
                    try ensureSiblingDirectory(at: siblingURL, fileManager: fileManager)
                    try writeMetadataFiles(plan: plan, siblingURL: siblingURL, fileManager: fileManager)
                    actualSiblingURL = siblingURL
                } catch {
                    // Filesystem failures are non-fatal for the SwiftData clone;
                    // they just mean the user has to inspect the SwiftData rows
                    // directly.
                    actualSiblingURL = nil
                }
            } else {
                do {
                    try ensureSiblingDirectory(at: siblingURL, fileManager: fileManager)
                    let sourceURL = URL(fileURLWithPath: sourceRoot, isDirectory: true)
                    bytesCopied = try copyWorkspace(
                        from: sourceURL,
                        to: siblingURL,
                        fileManager: fileManager
                    )
                    try writeMetadataFiles(plan: plan, siblingURL: siblingURL, fileManager: fileManager)
                    filesystemOutcome = .copied
                    actualSiblingURL = siblingURL
                } catch let error as RestoreIntoNewCopyError {
                    throw error
                } catch {
                    throw RestoreIntoNewCopyError.fileCopyFailed(siblingURL, error.localizedDescription)
                }
            }
        } else if plan.sourceRootPath == nil {
            filesystemOutcome = .notAttempted
        } else {
            filesystemOutcome = .skippedMissingRoot
        }

        try modelContext.save()

        let summary: String
        switch filesystemOutcome {
        case .copied:
            summary = "Restored into new copy at \(actualSiblingURL?.path ?? "n/a") with \(plan.taskClones.count) task / \(plan.operationClones.count) op / \(plan.auditClones.count) audit row clone(s)."
        case .skippedLargeSize:
            summary = "Cloned SwiftData rows; workspace copy skipped (\(RestoreIntoNewCopyMath.humanReadable(bytes: plan.estimatedSourceSizeBytes)) ≥ threshold). Re-run with large-size approval to duplicate files."
        case .skippedMissingRoot:
            summary = "Cloned SwiftData rows; source project root was not present on disk."
        case .notAttempted:
            summary = "Cloned SwiftData rows; no project root attached."
        }

        return RestoreIntoNewCopyResult(
            plan: plan,
            createdProjectID: createdProjectID,
            createdTaskIDs: createdTaskIDs,
            createdOperationIDs: createdOperationIDs,
            createdAuditIDs: createdAuditIDs,
            siblingDirectoryURL: actualSiblingURL,
            filesystemOutcome: filesystemOutcome,
            bytesCopied: bytesCopied,
            summary: summary
        )
    }

    private static func ensureSiblingDirectory(at url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path) {
            throw RestoreIntoNewCopyError.siblingDirectoryAlreadyExists(url)
        }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw RestoreIntoNewCopyError.directoryCreationFailed(url, error.localizedDescription)
        }
    }

    private static func writeMetadataFiles(
        plan: RestoreIntoNewCopyPlan,
        siblingURL: URL,
        fileManager: FileManager
    ) throws {
        let divergenceURL = siblingURL.appendingPathComponent("DIVERGENCE.md")
        try plan.agentNotesDivergenceNote.write(to: divergenceURL, atomically: true, encoding: .utf8)

        let agentNotesRelative = plan.projectClone?.clonedAgentNotesRelativePath ?? "AgentNotes.md"
        let agentNotesURL = siblingURL.appendingPathComponent(agentNotesRelative)
        let agentNotesParent = agentNotesURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: agentNotesParent.path) {
            try fileManager.createDirectory(at: agentNotesParent, withIntermediateDirectories: true)
        }
        try plan.agentNotesDivergenceNote.write(to: agentNotesURL, atomically: true, encoding: .utf8)

        let rowsDump = RestoreIntoNewCopyMath.encodeRowsDump(plan: plan)
        let rowsURL = siblingURL.appendingPathComponent("cloned-rows.json")
        try rowsDump.write(to: rowsURL, atomically: true, encoding: .utf8)
    }

    private static func copyWorkspace(
        from source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws -> Int64 {
        var bytes: Int64 = 0
        let resourceKeys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }
        for case let fileURL as URL in enumerator {
            let pathComponents = Set(fileURL.pathComponents)
            if !RestoreIntoNewCopyPlanner.excludedPathComponents.isDisjoint(with: pathComponents) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: resourceKeys)
            let isDir = values?.isDirectory == true
            let relative = fileURL.path.replacingOccurrences(of: source.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if relative.isEmpty { continue }
            let destURL = destination.appendingPathComponent(relative, isDirectory: isDir)
            if isDir {
                if !fileManager.fileExists(atPath: destURL.path) {
                    try? fileManager.createDirectory(at: destURL, withIntermediateDirectories: true)
                }
            } else {
                let parent = destURL.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: parent.path) {
                    try? fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                do {
                    if fileManager.fileExists(atPath: destURL.path) {
                        try fileManager.removeItem(at: destURL)
                    }
                    try fileManager.copyItem(at: fileURL, to: destURL)
                    if let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize {
                        bytes &+= Int64(size)
                    }
                } catch {
                    throw RestoreIntoNewCopyError.fileCopyFailed(fileURL, error.localizedDescription)
                }
            }
        }
        return bytes
    }
}

// MARK: - Workspace Copy Manager

/// Surfaces and manages divergence workspaces created by the
/// restore-into-new-copy workflow. Lives next to the workflow so the
/// Conflict Center can surface a `Manage Copies` section without
/// reaching into ContentView projects state.
struct DivergenceWorkspaceSummary: Sendable, Identifiable, Hashable {
    let id: String
    let projectID: String
    let name: String
    let rootPath: String?
    let conflictID: String?
    let createdAt: Date
    let exists: Bool
    let taskCount: Int
    let auditCount: Int
}

@MainActor
enum WorkspaceCopyManager {
    static let lineagePrefix = "restore::"
    static let nameMarker = "(divergence "

    static func listDivergenceWorkspaces(
        projects: [AgentProject],
        tasks: [AutonomyTaskRecord],
        audits: [AuditTrailRecord],
        fileManager: FileManager = .default
    ) -> [DivergenceWorkspaceSummary] {
        projects
            .filter { isDivergenceProject($0) }
            .map { project in
                let conflictID = conflictID(from: project)
                let exists = project.rootPath.map { fileManager.fileExists(atPath: $0) } ?? false
                let scopedTasks = tasks.filter { isCloned(taskID: $0.identifier, conflictID: conflictID) }
                let scopedAudits = audits.filter { audit in
                    isCloned(taskID: audit.taskID ?? "", conflictID: conflictID) ||
                        (audit.detail.contains("conflict \(conflictID ?? "")") && conflictID != nil)
                }
                return DivergenceWorkspaceSummary(
                    id: project.identifier,
                    projectID: project.identifier,
                    name: project.name,
                    rootPath: project.rootPath,
                    conflictID: conflictID,
                    createdAt: project.createdAt,
                    exists: exists,
                    taskCount: scopedTasks.count,
                    auditCount: scopedAudits.count
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func archive(
        workspace: DivergenceWorkspaceSummary,
        modelContext: ModelContext,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL? {
        guard let rootPath = workspace.rootPath,
              fileManager.fileExists(atPath: rootPath) else {
            return nil
        }
        let source = URL(fileURLWithPath: rootPath, isDirectory: true)
        let archived = source
            .deletingLastPathComponent()
            .appendingPathComponent("\(source.lastPathComponent)__archived")
        if fileManager.fileExists(atPath: archived.path) {
            try fileManager.removeItem(at: archived)
        }
        try fileManager.moveItem(at: source, to: archived)

        if let project = try projectRecord(id: workspace.projectID, in: modelContext) {
            project.rootPath = archived.path
            project.updatedAt = now
        }
        modelContext.insert(
            AuditTrailRecord(
                eventKind: "conflict.restoreIntoNewCopy.archived",
                detail: "Archived divergence workspace \(workspace.name) to \(archived.path).",
                createdAt: now
            )
        )
        try modelContext.save()
        return archived
    }

    static func delete(
        workspace: DivergenceWorkspaceSummary,
        modelContext: ModelContext,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws {
        if let rootPath = workspace.rootPath,
           fileManager.fileExists(atPath: rootPath) {
            try fileManager.removeItem(at: URL(fileURLWithPath: rootPath, isDirectory: true))
        }
        if let project = try projectRecord(id: workspace.projectID, in: modelContext) {
            modelContext.delete(project)
        }
        if let conflictID = workspace.conflictID {
            let tasks = try modelContext.fetch(FetchDescriptor<AutonomyTaskRecord>())
            for task in tasks where isCloned(taskID: task.identifier, conflictID: conflictID) {
                modelContext.delete(task)
            }
            let ops = try modelContext.fetch(FetchDescriptor<AutonomyOperationRecord>())
            for op in ops where isCloned(taskID: op.identifier, conflictID: conflictID) {
                modelContext.delete(op)
            }
            let audits = try modelContext.fetch(FetchDescriptor<AuditTrailRecord>())
            for audit in audits where isCloned(taskID: audit.identifier, conflictID: conflictID) {
                modelContext.delete(audit)
            }
        }
        modelContext.insert(
            AuditTrailRecord(
                eventKind: "conflict.restoreIntoNewCopy.deleted",
                detail: "Deleted divergence workspace \(workspace.name).",
                createdAt: now
            )
        )
        try modelContext.save()
    }

    static func isDivergenceProject(_ project: AgentProject) -> Bool {
        project.name.contains(nameMarker)
            || (project.rootPath?.contains("__divergence-") ?? false)
            || project.identifier.hasPrefix(lineagePrefix)
    }

    static func isCloned(taskID: String, conflictID: String?) -> Bool {
        guard taskID.hasPrefix(lineagePrefix) else { return false }
        if let conflictID {
            return taskID.contains("::\(conflictID)::")
        }
        return true
    }

    static func conflictID(from project: AgentProject) -> String? {
        if project.identifier.hasPrefix(lineagePrefix) {
            // restore::<conflictID>::project::<UUID>
            let parts = project.identifier.components(separatedBy: "::")
            if parts.count >= 2 {
                return parts[1]
            }
        }
        if let path = project.rootPath,
           let range = path.range(of: "__divergence-") {
            let suffix = path[range.upperBound...]
            return String(suffix).split(separator: "/").first.map(String.init)
        }
        return nil
    }

    private static func projectRecord(id: String, in modelContext: ModelContext) throws -> AgentProject? {
        let descriptor = FetchDescriptor<AgentProject>()
        let all = try modelContext.fetch(descriptor)
        return all.first(where: { $0.identifier == id })
    }
}

// MARK: - Math / formatting helpers

enum RestoreIntoNewCopyMath {
    static func humanReadable(bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 {
            return "\(bytes) \(units[index])"
        }
        return String(format: "%.1f %@", value, units[index])
    }

    static func encodeRowsDump(plan: RestoreIntoNewCopyPlan) -> String {
        var dict: [String: Any] = [:]
        dict["conflictID"] = plan.conflictID
        dict["entityID"] = plan.entityID
        dict["entityType"] = plan.entityType
        dict["sourceProjectID"] = plan.sourceProjectID ?? NSNull()
        dict["sourceProjectName"] = plan.sourceProjectName ?? NSNull()
        dict["taskClones"] = plan.taskClones.map { task -> [String: Any] in
            [
                "sourceTaskID": task.sourceTaskID,
                "clonedTaskID": task.clonedTaskID,
                "title": task.title,
                "status": task.status,
                "mode": task.mode,
            ]
        }
        dict["operationClones"] = plan.operationClones.map { op -> [String: Any] in
            [
                "sourceOperationID": op.sourceOperationID,
                "clonedOperationID": op.clonedOperationID,
                "operationKind": op.operationKind,
                "machineID": op.machineID,
                "lamportClock": op.lamportClock,
            ]
        }
        dict["auditClones"] = plan.auditClones.map { audit -> [String: Any] in
            [
                "sourceAuditID": audit.sourceAuditID,
                "clonedAuditID": audit.clonedAuditID,
                "eventKind": audit.eventKind,
            ]
        }
        dict["estimatedSourceSizeBytes"] = plan.estimatedSourceSizeBytes
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .prettyPrinted]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }
}
