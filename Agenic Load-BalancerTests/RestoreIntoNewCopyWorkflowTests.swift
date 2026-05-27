//
//  RestoreIntoNewCopyWorkflowTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint Q.4: regression coverage for the restore-into-new-copy
//  planner, applier, and workspace copy manager.
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@Suite("Sprint Q.4 restore-into-new-copy workflow")
struct RestoreIntoNewCopyWorkflowTests {
    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    private static func makePreview(
        entityID: String = "task-divergence",
        recordID: String = "conflict-q4"
    ) -> ConflictResolutionPreview {
        ConflictResolutionPreview(
            id: recordID,
            recordID: recordID,
            entityID: entityID,
            entityType: "autonomyTask",
            conflictKind: "operationLogDivergence",
            status: "open",
            local: OperationEnvelope(
                identifier: "op-local",
                entityID: entityID,
                entityType: "autonomyTask",
                operationKind: "setStatus",
                lamportClock: 5,
                machineID: "mac-a",
                payload: ["status": "running"]
            ),
            remote: OperationEnvelope(
                identifier: "op-remote",
                entityID: entityID,
                entityType: "autonomyTask",
                operationKind: "setStatus",
                lamportClock: 5,
                machineID: "mac-b",
                payload: ["status": "blocked"]
            ),
            localCreatedAt: Date(timeIntervalSince1970: 1_000),
            remoteCreatedAt: Date(timeIntervalSince1970: 1_010),
            affectedEntityCount: 1,
            affectedFieldCount: 1,
            sourceRunID: nil,
            sourceTaskID: entityID,
            sourcePlanID: nil,
            restoreSnapshotID: nil,
            outcomeSummary: "Concurrent non-commutative edits require review.",
            recommendedAction: nil,
            proposedPayload: [:],
            warnings: [],
            resolutionJSON: "{}",
            createdAt: Date(timeIntervalSince1970: 1_020)
        )
    }

    @Test func plannerProducesScopedCloneFromAutonomyTaskDivergence() {
        let preview = Self.makePreview()
        let task = AutonomyTaskRecord(
            identifier: "task-divergence",
            goalID: "goal-1",
            title: "Refactor cluster scheduler",
            detail: "Reconcile cluster scheduler logic.",
            status: "blocked",
            mode: AgentExecutionMode.implementation.rawValue,
            dependencyIDsJSON: "[]"
        )
        let unrelated = AutonomyTaskRecord(
            identifier: "task-other",
            title: "Unrelated",
            detail: "Should not be cloned",
            status: "planned",
            mode: AgentExecutionMode.planOnly.rawValue
        )
        let operation = AutonomyOperationRecord(
            identifier: "op-1",
            entityID: "task-divergence",
            entityType: "autonomyTask",
            operationKind: "setStatus",
            lamportClock: 5,
            machineID: "mac-a",
            payloadJSON: #"{"status":"running"}"#
        )
        let unrelatedOp = AutonomyOperationRecord(
            identifier: "op-other",
            entityID: "task-other",
            entityType: "autonomyTask",
            operationKind: "setStatus",
            machineID: "mac-c"
        )
        let audit = AuditTrailRecord(
            identifier: "audit-1",
            goalID: "goal-1",
            taskID: "task-divergence",
            eventKind: "autonomy.dispatch.prepared",
            detail: "Prepared dispatch"
        )

        let plan = RestoreIntoNewCopyPlanner.plan(
            for: preview,
            sourceProject: nil,
            candidateTasks: [task, unrelated],
            candidateOperations: [operation, unrelatedOp],
            candidateAudits: [audit]
        )

        #expect(plan.conflictID == "conflict-q4")
        #expect(plan.taskClones.count == 1)
        #expect(plan.taskClones.first?.sourceTaskID == "task-divergence")
        #expect(plan.taskClones.first?.clonedTaskID.hasPrefix("restore::conflict-q4::task::") == true)
        #expect(plan.taskClones.first?.title.contains("(divergence ") == true)
        #expect(plan.operationClones.count == 1)
        #expect(plan.operationClones.first?.sourceOperationID == "op-1")
        #expect(plan.auditClones.count == 1)
        #expect(plan.auditClones.first?.sourceAuditID == "audit-1")
        #expect(plan.siblingDirectoryURL == nil)
        #expect(plan.requiresLargeSizeApproval == false)
    }

    @Test func plannerOmitsFilesystemSiblingWhenSourceRootIsMissing() {
        let preview = Self.makePreview()
        let project = AgentProject(
            identifier: "proj-1",
            name: "Demo",
            rootPath: "/nonexistent/path/Demo"
        )

        let plan = RestoreIntoNewCopyPlanner.plan(
            for: preview,
            sourceProject: project,
            candidateTasks: [],
            candidateOperations: [],
            candidateAudits: []
        )

        #expect(plan.siblingDirectoryURL == nil)
        #expect(plan.estimatedSourceSizeBytes == 0)
        #expect(plan.projectClone?.clonedRootPath == nil)
    }

    @MainActor
    @Test func applierInsertsClonedRowsWithoutMutatingOriginals() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let preview = Self.makePreview()
        let task = AutonomyTaskRecord(
            identifier: "task-divergence",
            goalID: "goal-1",
            title: "Refactor cluster scheduler",
            detail: "Reconcile cluster scheduler logic.",
            status: "blocked",
            mode: AgentExecutionMode.implementation.rawValue
        )
        context.insert(task)
        let auditOriginal = AuditTrailRecord(
            identifier: "audit-1",
            goalID: "goal-1",
            taskID: "task-divergence",
            eventKind: "autonomy.dispatch.prepared",
            detail: "Prepared dispatch"
        )
        context.insert(auditOriginal)
        try context.save()

        let plan = RestoreIntoNewCopyPlanner.plan(
            for: preview,
            sourceProject: nil,
            candidateTasks: [task],
            candidateOperations: [],
            candidateAudits: [auditOriginal]
        )

        let result = try RestoreIntoNewCopyApplier.apply(plan: plan, modelContext: context)

        #expect(result.createdTaskIDs.count == 1)
        #expect(result.createdAuditIDs.count >= 1)
        #expect(result.filesystemOutcome == .notAttempted)

        let allTasks = try context.fetch(FetchDescriptor<AutonomyTaskRecord>())
        let original = try #require(allTasks.first(where: { $0.identifier == "task-divergence" }))
        #expect(original.status == "blocked")
        #expect(original.title == "Refactor cluster scheduler")
        #expect(allTasks.contains(where: { $0.identifier.hasPrefix("restore::conflict-q4::task::") }))

        let allAudits = try context.fetch(FetchDescriptor<AuditTrailRecord>())
        let originalAudit = try #require(allAudits.first(where: { $0.identifier == "audit-1" }))
        #expect(originalAudit.detail == "Prepared dispatch")
        #expect(allAudits.contains(where: { $0.eventKind == "conflict.restoreIntoNewCopy.applied" }))
    }

    @MainActor
    @Test func applierCreatesSiblingDirectoryAndDivergenceNoteWhenRootExists() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreIntoNewCopy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let projectRoot = tempBase.appendingPathComponent("DemoProject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let sampleFile = projectRoot.appendingPathComponent("README.md")
        try "Hello divergence".write(to: sampleFile, atomically: true, encoding: .utf8)

        let project = AgentProject(
            identifier: "proj-q4",
            name: "Demo Project",
            rootPath: projectRoot.path
        )
        context.insert(project)
        let task = AutonomyTaskRecord(
            identifier: "task-divergence",
            goalID: "goal-1",
            title: "Refactor cluster scheduler",
            detail: "Reconcile cluster scheduler logic.",
            status: "blocked",
            mode: AgentExecutionMode.implementation.rawValue
        )
        context.insert(task)
        try context.save()

        let preview = Self.makePreview()
        let plan = RestoreIntoNewCopyPlanner.plan(
            for: preview,
            sourceProject: project,
            candidateTasks: [task],
            candidateOperations: [],
            candidateAudits: []
        )

        #expect(plan.siblingDirectoryURL != nil)
        #expect(plan.requiresLargeSizeApproval == false)

        let result = try RestoreIntoNewCopyApplier.apply(plan: plan, modelContext: context)

        let siblingURL = try #require(result.siblingDirectoryURL)
        #expect(result.filesystemOutcome == .copied)
        #expect(FileManager.default.fileExists(atPath: siblingURL.appendingPathComponent("DIVERGENCE.md").path))
        #expect(FileManager.default.fileExists(atPath: siblingURL.appendingPathComponent("AgentNotes.md").path))
        #expect(FileManager.default.fileExists(atPath: siblingURL.appendingPathComponent("cloned-rows.json").path))
        #expect(FileManager.default.fileExists(atPath: siblingURL.appendingPathComponent("README.md").path))

        let agentNotesContents = try String(contentsOf: siblingURL.appendingPathComponent("AgentNotes.md"), encoding: .utf8)
        #expect(agentNotesContents.contains("Divergence Note"))
        #expect(agentNotesContents.contains("conflict-q4"))

        let projects = try context.fetch(FetchDescriptor<AgentProject>())
        #expect(projects.contains(where: { $0.name.contains("(divergence ") }))
    }

    @MainActor
    @Test func applierRefusesLargeFileCopyWithoutApprovalButStillClonesRows() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreIntoNewCopyLarge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let projectRoot = tempBase.appendingPathComponent("LargeProject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        // Drop a single 4-byte file so the directory walk returns nonzero.
        let placeholder = projectRoot.appendingPathComponent("placeholder.txt")
        try "data".write(to: placeholder, atomically: true, encoding: .utf8)

        let project = AgentProject(
            identifier: "proj-large",
            name: "Large Project",
            rootPath: projectRoot.path
        )
        context.insert(project)
        let task = AutonomyTaskRecord(
            identifier: "task-divergence",
            goalID: "goal-large",
            title: "Reconcile",
            detail: "Reconcile",
            status: "blocked",
            mode: AgentExecutionMode.implementation.rawValue
        )
        context.insert(task)
        try context.save()

        let preview = Self.makePreview()
        // Force the size threshold to 1 byte so the placeholder file forces the warning.
        let plan = RestoreIntoNewCopyPlanner.plan(
            for: preview,
            sourceProject: project,
            candidateTasks: [task],
            candidateOperations: [],
            candidateAudits: [],
            largeSizeThresholdBytes: 1
        )

        #expect(plan.requiresLargeSizeApproval == true)

        let result = try RestoreIntoNewCopyApplier.apply(
            plan: plan,
            allowLargeCopy: false,
            modelContext: context
        )

        #expect(result.filesystemOutcome == .skippedLargeSize)
        #expect(result.createdTaskIDs.count == 1)

        let siblingURL = try #require(result.siblingDirectoryURL)
        // Metadata files should still land so the user has somewhere to anchor.
        #expect(FileManager.default.fileExists(atPath: siblingURL.appendingPathComponent("DIVERGENCE.md").path))
        // The placeholder source file should NOT have been duplicated.
        #expect(!FileManager.default.fileExists(atPath: siblingURL.appendingPathComponent("placeholder.txt").path))
    }

    @MainActor
    @Test func workspaceCopyManagerListsAndDeletesDivergenceWorkspaces() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreCopyManager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let projectRoot = tempBase.appendingPathComponent("DemoProject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try "Hello".write(to: projectRoot.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let project = AgentProject(
            identifier: "proj-mgr",
            name: "Demo Project",
            rootPath: projectRoot.path
        )
        context.insert(project)
        let task = AutonomyTaskRecord(
            identifier: "task-divergence",
            goalID: "goal-mgr",
            title: "Reconcile",
            detail: "Reconcile",
            status: "blocked",
            mode: AgentExecutionMode.implementation.rawValue
        )
        context.insert(task)
        try context.save()

        let preview = Self.makePreview()
        let plan = RestoreIntoNewCopyPlanner.plan(
            for: preview,
            sourceProject: project,
            candidateTasks: [task],
            candidateOperations: [],
            candidateAudits: []
        )
        _ = try RestoreIntoNewCopyApplier.apply(plan: plan, modelContext: context)

        let projects = try context.fetch(FetchDescriptor<AgentProject>())
        let tasks = try context.fetch(FetchDescriptor<AutonomyTaskRecord>())
        let audits = try context.fetch(FetchDescriptor<AuditTrailRecord>())

        let workspaces = WorkspaceCopyManager.listDivergenceWorkspaces(
            projects: projects,
            tasks: tasks,
            audits: audits
        )
        #expect(workspaces.count == 1)
        let workspace = try #require(workspaces.first)
        #expect(workspace.conflictID == "conflict-q4")
        #expect(workspace.exists == true)
        #expect(workspace.taskCount == 1)

        try WorkspaceCopyManager.delete(workspace: workspace, modelContext: context)
        let projectsAfter = try context.fetch(FetchDescriptor<AgentProject>())
        let tasksAfter = try context.fetch(FetchDescriptor<AutonomyTaskRecord>())

        #expect(projectsAfter.contains(where: { $0.identifier == "proj-mgr" }))
        #expect(!projectsAfter.contains(where: { $0.name.contains("(divergence ") }))
        #expect(tasksAfter.contains(where: { $0.identifier == "task-divergence" }))
        #expect(!tasksAfter.contains(where: { $0.identifier.hasPrefix("restore::") }))
        if let siblingURL = workspace.rootPath {
            #expect(!FileManager.default.fileExists(atPath: siblingURL))
        }
    }

    @MainActor
    @Test func workspaceCopyManagerArchivesSiblingDirectory() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreCopyArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let projectRoot = tempBase.appendingPathComponent("DemoProject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try "Hello".write(to: projectRoot.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let project = AgentProject(
            identifier: "proj-arch",
            name: "Demo Project",
            rootPath: projectRoot.path
        )
        context.insert(project)
        try context.save()

        let preview = Self.makePreview()
        let plan = RestoreIntoNewCopyPlanner.plan(
            for: preview,
            sourceProject: project,
            candidateTasks: [],
            candidateOperations: [],
            candidateAudits: []
        )
        let applied = try RestoreIntoNewCopyApplier.apply(plan: plan, modelContext: context)

        let projects = try context.fetch(FetchDescriptor<AgentProject>())
        let tasks = try context.fetch(FetchDescriptor<AutonomyTaskRecord>())
        let audits = try context.fetch(FetchDescriptor<AuditTrailRecord>())
        let workspaces = WorkspaceCopyManager.listDivergenceWorkspaces(
            projects: projects,
            tasks: tasks,
            audits: audits
        )
        let workspace = try #require(workspaces.first)

        _ = applied
        let archivedURL = try #require(try WorkspaceCopyManager.archive(workspace: workspace, modelContext: context))
        #expect(archivedURL.lastPathComponent.hasSuffix("__archived"))
        #expect(FileManager.default.fileExists(atPath: archivedURL.path))
        // Original sibling location no longer exists.
        if let oldRoot = workspace.rootPath {
            #expect(!FileManager.default.fileExists(atPath: oldRoot))
        }

        // The project row's rootPath should now point at the archived location.
        let refreshed = try context.fetch(FetchDescriptor<AgentProject>())
        let archivedProject = try #require(refreshed.first(where: { $0.identifier == workspace.projectID }))
        #expect(archivedProject.rootPath == archivedURL.path)
    }

    @Test func humanReadableByteFormattingScalesAcrossUnits() {
        #expect(RestoreIntoNewCopyMath.humanReadable(bytes: 512) == "512 B")
        #expect(RestoreIntoNewCopyMath.humanReadable(bytes: 2_048).hasSuffix("KB"))
        #expect(RestoreIntoNewCopyMath.humanReadable(bytes: 5 * 1024 * 1024).hasSuffix("MB"))
        #expect(RestoreIntoNewCopyMath.humanReadable(bytes: 3 * 1024 * 1024 * 1024).hasSuffix("GB"))
    }
}
