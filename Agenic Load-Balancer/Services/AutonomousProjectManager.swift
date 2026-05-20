//
//  AutonomousProjectManager.swift
//  Agenic Load-Balancer
//
//  Phase 7.6: safe goal-to-plan foundation for autonomous project work.
//

import Foundation
import SwiftData

struct AutonomousGoalRequest: Sendable, Hashable {
    var title: String
    var goalDescription: String
    var projectID: String?
    var projectRootPath: String?
    var autonomyPolicy: AutonomyPolicy
}

struct AutonomousTaskDraft: Sendable, Hashable, Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var mode: AgentExecutionMode
    var dependencyTitles: [String]
    var validationCommand: String?
}

struct AutonomousPlanDraft: Sendable, Hashable {
    var summary: String
    var tasks: [AutonomousTaskDraft]
}

struct PersistedAutonomousPlan: Sendable, Hashable {
    var goalID: String
    var planID: String
    var policyID: String
    var taskIDsByTitle: [String: String]
}

enum AutonomyExecutionError: Error, Sendable, LocalizedError, Equatable {
    case missingTask(String)
    case missingProjectRoot
    case denied(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingTask(let taskID):
            return "Autonomy task not found: \(taskID)"
        case .missingProjectRoot:
            return "The selected project has no local root path."
        case .denied(let reason):
            return reason
        case .saveFailed(let reason):
            return "Autonomy persistence failed: \(reason)"
        }
    }
}

protocol GoalPlanning: Sendable {
    func plan(request: AutonomousGoalRequest) async throws -> AutonomousPlanDraft
}

struct DeterministicGoalPlanner: GoalPlanning {
    func plan(request: AutonomousGoalRequest) async throws -> AutonomousPlanDraft {
        AutonomousPlanDraft(
            summary: "Plan for \(request.title)",
            tasks: [
                AutonomousTaskDraft(
                    title: "Inspect repo contract",
                    detail: "Read AgentNotes.md, PLAN.md, AgentPlan.md, README, project files, and git status before editing.",
                    mode: .readReview,
                    dependencyTitles: [],
                    validationCommand: nil
                ),
                AutonomousTaskDraft(
                    title: "Create implementation plan",
                    detail: "Break the goal into scoped tasks with file ownership and validation gates.",
                    mode: .planOnly,
                    dependencyTitles: ["Inspect repo contract"],
                    validationCommand: nil
                ),
                AutonomousTaskDraft(
                    title: "Execute approved implementation",
                    detail: "Dispatch the best provider for the approved task, stream logs, and record outcomes.",
                    mode: .implementation,
                    dependencyTitles: ["Create implementation plan"],
                    validationCommand: validationCommand(for: request.projectRootPath)
                ),
                AutonomousTaskDraft(
                    title: "Validate and checkpoint",
                    detail: "Run validation gates, record results, update AgentNotes, and checkpoint only after approval.",
                    mode: .testBuild,
                    dependencyTitles: ["Execute approved implementation"],
                    validationCommand: validationCommand(for: request.projectRootPath)
                ),
            ]
        )
    }

    private func validationCommand(for rootPath: String?) -> String? {
        guard rootPath != nil else { return nil }
        return """
        DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test
        """
    }
}

actor AutonomousProjectManager {
    private let planner: any GoalPlanning
    private let policyEvaluator: AutonomyPolicyEvaluator

    init(
        planner: any GoalPlanning = DeterministicGoalPlanner(),
        policyEvaluator: AutonomyPolicyEvaluator = AutonomyPolicyEvaluator()
    ) {
        self.planner = planner
        self.policyEvaluator = policyEvaluator
    }

    func draftPlan(request: AutonomousGoalRequest) async throws -> AutonomousPlanDraft {
        try await planner.plan(request: request)
    }

    func evaluate(
        task: AutonomousTaskDraft,
        request: AutonomousGoalRequest,
        estimatedCostUSD: Double
    ) -> AutonomyPolicyDecision {
        policyEvaluator.evaluateRun(
            mode: task.mode,
            estimatedCostUSD: estimatedCostUSD,
            policy: request.autonomyPolicy
        )
    }
}

@MainActor
enum AutonomyPersistence {
    static func persistDraftPlan(
        request: AutonomousGoalRequest,
        draft: AutonomousPlanDraft,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws -> PersistedAutonomousPlan {
        let goalID = UUID().uuidString
        let planID = UUID().uuidString
        let policyID = UUID().uuidString

        let taskIDsByTitle = Dictionary(
            uniqueKeysWithValues: draft.tasks.map { ($0.title, UUID().uuidString) }
        )
        let taskIDs = draft.tasks.compactMap { taskIDsByTitle[$0.title] }

        let goal = AutonomyGoalRecord(
            identifier: goalID,
            projectID: request.projectID,
            title: request.title,
            goalDescription: request.goalDescription,
            status: CoordinationStatus.planned.rawValue,
            autonomyLevel: request.autonomyPolicy.level.rawValue,
            createdAt: now,
            updatedAt: now
        )
        let plan = AutonomyPlanRecord(
            identifier: planID,
            goalID: goalID,
            summary: draft.summary,
            taskIDsJSON: encodeStrings(taskIDs),
            createdAt: now,
            updatedAt: now
        )
        let policy = AutonomyPolicyRecord(
            identifier: policyID,
            projectID: request.projectID,
            policyJSON: encodePolicy(request.autonomyPolicy),
            createdAt: now,
            updatedAt: now
        )
        let tasks = draft.tasks.map { task in
            AutonomyTaskRecord(
                identifier: taskIDsByTitle[task.title] ?? UUID().uuidString,
                goalID: goalID,
                title: task.title,
                detail: task.detail,
                status: CoordinationStatus.planned.rawValue,
                mode: task.mode.rawValue,
                dependencyIDsJSON: encodeStrings(task.dependencyTitles.compactMap { taskIDsByTitle[$0] }),
                validationCommand: task.validationCommand,
                createdAt: now,
                updatedAt: now
            )
        }

        modelContext.insert(goal)
        modelContext.insert(plan)
        modelContext.insert(policy)
        tasks.forEach(modelContext.insert)
        modelContext.insert(
            AuditTrailRecord(
                goalID: goalID,
                eventKind: "autonomy.plan.persisted",
                detail: "Persisted \(tasks.count) task(s) for \(request.autonomyPolicy.level.label).",
                createdAt: now
            )
        )
        modelContext.insert(
            AutonomyOperationRecord(
                entityID: planID,
                entityType: "autonomyPlan",
                operationKind: "persistDraft",
                lamportClock: 1,
                machineID: localMachineID(),
                payloadJSON: encodeStrings(taskIDs),
                createdAt: now
            )
        )

        do {
            try modelContext.save()
        } catch {
            throw AutonomyExecutionError.saveFailed(error.localizedDescription)
        }

        return PersistedAutonomousPlan(
            goalID: goalID,
            planID: planID,
            policyID: policyID,
            taskIDsByTitle: taskIDsByTitle
        )
    }

    static func markTaskDispatchPrepared(
        taskID: String,
        providerID: String,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws {
        let task = try fetchTask(taskID, in: modelContext)
        task.assignedProviderID = providerID
        task.updatedAt = now
        modelContext.insert(
            AuditTrailRecord(
                goalID: task.goalID,
                taskID: task.identifier,
                eventKind: "autonomy.dispatch.prepared",
                detail: "Prepared approval-gated dispatch through \(providerID).",
                createdAt: now
            )
        )
        try save(modelContext)
    }

    static func updateTaskStatus(
        taskID: String,
        status: CoordinationStatus,
        detail: String,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws {
        let task = try fetchTask(taskID, in: modelContext)
        task.status = status.rawValue
        task.updatedAt = now
        modelContext.insert(
            AuditTrailRecord(
                goalID: task.goalID,
                taskID: task.identifier,
                eventKind: "autonomy.task.\(status.rawValue)",
                detail: detail,
                createdAt: now
            )
        )
        try save(modelContext)
    }

    static func runValidationGate(
        taskID: String,
        command: String,
        workingDirectory: String?,
        policy: AutonomyPolicy,
        runner: any ValidationGateRunning,
        modelContext: ModelContext,
        now: Date = Date()
    ) async throws -> ValidationGateResult {
        guard let workingDirectory, !workingDirectory.isEmpty else {
            throw AutonomyExecutionError.missingProjectRoot
        }
        let decision = AutonomyPolicyEvaluator().evaluateRun(
            mode: .testBuild,
            estimatedCostUSD: 0,
            policy: policy
        )
        if case .denied(let reason) = decision {
            throw AutonomyExecutionError.denied(reason)
        }

        let task = try fetchTask(taskID, in: modelContext)
        let gate = ValidationGateRecord(
            taskID: task.identifier,
            command: command,
            status: "running",
            startedAt: now
        )
        task.status = CoordinationStatus.inProgress.rawValue
        task.updatedAt = now
        modelContext.insert(gate)
        modelContext.insert(
            AuditTrailRecord(
                goalID: task.goalID,
                taskID: task.identifier,
                eventKind: "autonomy.validation.started",
                detail: command,
                createdAt: now
            )
        )
        try save(modelContext)

        let result = await runner.run(command: command, workingDirectory: workingDirectory)
        gate.status = result.passed ? "passed" : "failed"
        gate.outputExcerpt = result.outputExcerpt
        gate.startedAt = result.startedAt
        gate.endedAt = result.endedAt
        task.status = result.passed ? CoordinationStatus.completed.rawValue : CoordinationStatus.conflict.rawValue
        task.updatedAt = result.endedAt
        modelContext.insert(
            AuditTrailRecord(
                goalID: task.goalID,
                taskID: task.identifier,
                eventKind: result.passed ? "autonomy.validation.passed" : "autonomy.validation.failed",
                detail: "Exit \(result.exitCode)",
                createdAt: result.endedAt
            )
        )
        try save(modelContext)
        return result
    }

    static func encodeStrings(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    static func decodeStrings(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func encodePolicy(_ policy: AutonomyPolicy) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(policy),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func fetchTask(_ taskID: String, in modelContext: ModelContext) throws -> AutonomyTaskRecord {
        let descriptor = FetchDescriptor<AutonomyTaskRecord>()
        guard let task = try modelContext.fetch(descriptor).first(where: { $0.identifier == taskID }) else {
            throw AutonomyExecutionError.missingTask(taskID)
        }
        return task
    }

    private static func save(_ modelContext: ModelContext) throws {
        do {
            try modelContext.save()
        } catch {
            throw AutonomyExecutionError.saveFailed(error.localizedDescription)
        }
    }

    private static func localMachineID() -> String {
        Host.current().localizedName ?? "local-machine"
    }
}
