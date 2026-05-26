//
//  AutonomousLoopScheduler.swift
//  Agenic Load-Balancer
//
//  Sprint Q.3: bounded multi-step autonomy scheduler. Walks an already-
//  persisted `AutonomousPlanDraft` task-by-task in topological dependency
//  order, evaluating each task against the active `AutonomyPolicy`. The
//  scheduler:
//
//   - marks low-risk inspection / plan-only / docs-only tasks as
//     completed without ever spawning a provider run (those modes are
//     "advisory" inside the dispatcher and the autonomy state-machine);
//   - runs the validation gate when a task carries a validation command;
//   - halts immediately the moment a task would require approval or is
//     denied by the policy, returning the index + reason to the caller
//     so the existing approval sheet can pick it up;
//   - halts after the configured validation-failure or iteration cap is
//     reached;
//   - writes audit-trail rows for every iteration boundary so the
//     History view and Conflict Center can rebuild what happened later.
//
//  The scheduler never launches a real `RunDispatcher`. The dispatcher
//  remains approval-gated; the scheduler exists so the autonomy surface
//  can drive a *plan* across multiple sub-sprints without the user
//  manually re-clicking through every low-risk task.
//

import Foundation
import SwiftData

/// Caps on a single scheduler run. All defaults are conservative on
/// purpose — autonomy stays deliberately bounded per the safety
/// principles in AgentPlan.md.
struct AutonomousLoopBudget: Sendable, Hashable {
    var maxIterations: Int
    var maxValidationFailures: Int
    /// Cap on the number of approval-gated tasks the scheduler may
    /// surface in a single run before halting. Keeps a misconfigured
    /// plan from generating dozens of approval prompts in one pass.
    var maxApprovalsBeforeHalt: Int

    static let `default` = AutonomousLoopBudget(
        maxIterations: 12,
        maxValidationFailures: 1,
        maxApprovalsBeforeHalt: 1
    )
}

/// One iteration's worth of state, recorded into the report so callers
/// can render the full chain in the autonomy control room.
struct AutonomousLoopIteration: Sendable, Hashable, Identifiable, Codable {
    enum Status: String, Sendable, Hashable, Codable {
        /// The task was inspection/plan-only/docs-only — marked complete
        /// without invoking a validation gate or provider.
        case completedAdvisory
        /// Validation gate ran and passed.
        case validationPassed
        /// Validation gate ran and failed; failure counter advanced.
        case validationFailed
        /// Policy returned `.requiresApproval`; scheduler halted at this
        /// iteration so the existing approval sheet can pick it up.
        case approvalRequired
        /// Policy returned `.denied`; scheduler halted because the task
        /// is outside the active trust lane.
        case denied
        /// Task was skipped because its dependencies were unresolved.
        case dependenciesUnresolved
    }

    let index: Int
    let taskID: String
    let taskTitle: String
    let mode: String
    let status: Status
    let detail: String
    let validationCommand: String?
    let validationExitCode: Int32?
    let occurredAt: Date

    var id: String { "\(index):\(taskID)" }

    private enum CodingKeys: String, CodingKey {
        case index, taskID, taskTitle, mode, status, detail, validationCommand, validationExitCode, occurredAt
    }
}

/// Why the scheduler stopped walking the plan.
enum AutonomousLoopHaltReason: Sendable, Hashable {
    case completed
    case approvalRequired(taskID: String, reason: String)
    case denied(taskID: String, reason: String)
    case validationFailureCap(failures: Int)
    case iterationCap(max: Int)
    case approvalCap(max: Int)
    case dependencyDeadlock(unresolvedTaskIDs: [String])

    /// Stable identifier for the case used for persisted records, UI
    /// chips, and analytics. The associated values land in `label`.
    var kind: String {
        switch self {
        case .completed: "completed"
        case .approvalRequired: "approvalRequired"
        case .denied: "denied"
        case .validationFailureCap: "validationFailureCap"
        case .iterationCap: "iterationCap"
        case .approvalCap: "approvalCap"
        case .dependencyDeadlock: "dependencyDeadlock"
        }
    }

    var label: String {
        switch self {
        case .completed:
            return "Plan walked to completion."
        case .approvalRequired(let taskID, let reason):
            return "Approval required at \(taskID): \(reason)"
        case .denied(let taskID, let reason):
            return "Policy denied \(taskID): \(reason)"
        case .validationFailureCap(let failures):
            return "Validation failure cap (\(failures)) reached."
        case .iterationCap(let max):
            return "Iteration cap (\(max)) reached."
        case .approvalCap(let max):
            return "Approval cap (\(max)) reached in a single pass."
        case .dependencyDeadlock(let ids):
            return "Dependency deadlock: \(ids.joined(separator: ", "))"
        }
    }
}

/// Final report produced by the scheduler. Records the full iteration
/// history plus the halt reason so the autonomy control room can render
/// the timeline and the next approval prompt in one pass.
struct AutonomousLoopRunReport: Sendable, Hashable {
    let goalID: String
    let planID: String
    let iterations: [AutonomousLoopIteration]
    let haltReason: AutonomousLoopHaltReason
    let validationFailureCount: Int
    let approvalSurfaceCount: Int
    let completedTaskIDs: [String]
    let pendingTaskIDs: [String]
    let startedAt: Date
    let endedAt: Date

    /// Convenience hooks used by the UI to colour the iteration timeline.
    var passed: Bool {
        if case .completed = haltReason { return true }
        return false
    }

    var didStop: Bool {
        if case .completed = haltReason { return false }
        return true
    }
}

/// Tasks that the scheduler can mark complete advisorily without going
/// through the validation gate (or a real provider run). These match
/// `AgentExecutionMode` values that the dispatcher treats as advisory.
private let advisoryModeRawValues: Set<String> = [
    AgentExecutionMode.recommendOnly.rawValue,
    AgentExecutionMode.readReview.rawValue,
    AgentExecutionMode.planOnly.rawValue,
]

/// Stateless scheduler — the only "state" is the policy evaluator and
/// the injectable `now` clock. The `run(...)` entry point is MainActor
/// because every SwiftData mutation it performs needs to happen on the
/// main actor; the actual validation gate runs on a detached task via
/// the supplied `ValidationGateRunning`.
struct AutonomousLoopScheduler: Sendable {
    private let policyEvaluator: AutonomyPolicyEvaluator
    private let now: @Sendable () -> Date

    init(
        policyEvaluator: AutonomyPolicyEvaluator = AutonomyPolicyEvaluator(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.policyEvaluator = policyEvaluator
        self.now = now
    }

    /// Run the scheduler against an already-persisted plan. The caller
    /// is responsible for supplying the same `AutonomyPolicy` that was
    /// used at plan time so policy decisions stay consistent across the
    /// lifetime of the goal.
    @MainActor
    func run(
        plan: PersistedAutonomousPlan,
        policy: AutonomyPolicy,
        projectRootPath: String?,
        validationRunner: any ValidationGateRunning,
        budget: AutonomousLoopBudget = .default,
        modelContext: ModelContext
    ) async -> AutonomousLoopRunReport {
        let startedAt = now()
        var iterations: [AutonomousLoopIteration] = []
        var validationFailures = 0
        var approvalsSurfaced = 0
        var completedTaskIDs: [String] = []
        var haltReason: AutonomousLoopHaltReason = .completed

        let allTaskIDs = plan.taskIDsByTitle.values.map { String($0) }
        let tasks = AutonomousLoopFetcher.tasks(in: modelContext, ids: allTaskIDs)
        let orderedTaskIDs = AutonomousLoopOrder.topologicalTaskIDs(
            tasks: tasks
        )

        var consumed: Set<String> = []

        scheduleLoop: for index in 0..<orderedTaskIDs.count {
            if iterations.count >= budget.maxIterations {
                haltReason = .iterationCap(max: budget.maxIterations)
                break
            }
            let taskID = orderedTaskIDs[index]
            guard let task = tasks.first(where: { $0.identifier == taskID }) else {
                continue
            }
            // Already-completed tasks (e.g. from a prior run) keep
            // their state and feed forward into completedTaskIDs.
            if task.status == CoordinationStatus.completed.rawValue ||
                task.status == CoordinationStatus.checkpointed.rawValue {
                completedTaskIDs.append(taskID)
                consumed.insert(taskID)
                continue
            }
            let dependencies = AutonomyPersistence.decodeStrings(task.dependencyIDsJSON)
            let unresolved = dependencies.filter { !consumed.contains($0) }
            if !unresolved.isEmpty {
                iterations.append(
                    AutonomousLoopIteration(
                        index: iterations.count,
                        taskID: taskID,
                        taskTitle: task.title,
                        mode: task.mode,
                        status: .dependenciesUnresolved,
                        detail: "Pending dependencies: \(unresolved.joined(separator: ", "))",
                        validationCommand: task.validationCommand,
                        validationExitCode: nil,
                        occurredAt: now()
                    )
                )
                haltReason = .dependencyDeadlock(unresolvedTaskIDs: unresolved)
                break
            }

            let mode = AgentExecutionMode(rawValue: task.mode) ?? .planOnly
            let decision = policyEvaluator.evaluateRun(
                mode: mode,
                estimatedCostUSD: 0,
                policy: policy
            )
            switch decision {
            case .denied(let reason):
                iterations.append(
                    AutonomousLoopIteration(
                        index: iterations.count,
                        taskID: taskID,
                        taskTitle: task.title,
                        mode: task.mode,
                        status: .denied,
                        detail: reason,
                        validationCommand: task.validationCommand,
                        validationExitCode: nil,
                        occurredAt: now()
                    )
                )
                AutonomousLoopAudit.append(
                    goalID: task.goalID,
                    taskID: taskID,
                    eventKind: "autonomy.loop.denied",
                    detail: reason,
                    occurredAt: now(),
                    modelContext: modelContext
                )
                haltReason = .denied(taskID: taskID, reason: reason)
                break scheduleLoop

            case .requiresApproval(let reason):
                approvalsSurfaced += 1
                iterations.append(
                    AutonomousLoopIteration(
                        index: iterations.count,
                        taskID: taskID,
                        taskTitle: task.title,
                        mode: task.mode,
                        status: .approvalRequired,
                        detail: reason,
                        validationCommand: task.validationCommand,
                        validationExitCode: nil,
                        occurredAt: now()
                    )
                )
                AutonomousLoopAudit.append(
                    goalID: task.goalID,
                    taskID: taskID,
                    eventKind: "autonomy.loop.approvalRequired",
                    detail: reason,
                    occurredAt: now(),
                    modelContext: modelContext
                )
                if approvalsSurfaced >= budget.maxApprovalsBeforeHalt {
                    haltReason = .approvalRequired(taskID: taskID, reason: reason)
                    break scheduleLoop
                }
                continue

            case .allowed:
                // Advisory modes complete without firing the validation
                // gate or any provider call.
                if advisoryModeRawValues.contains(task.mode), (task.validationCommand?.isEmpty ?? true) {
                    task.status = CoordinationStatus.completed.rawValue
                    task.updatedAt = now()
                    completedTaskIDs.append(taskID)
                    consumed.insert(taskID)
                    iterations.append(
                        AutonomousLoopIteration(
                            index: iterations.count,
                            taskID: taskID,
                            taskTitle: task.title,
                            mode: task.mode,
                            status: .completedAdvisory,
                            detail: "Advisory \(task.mode) task; no provider run required.",
                            validationCommand: nil,
                            validationExitCode: nil,
                            occurredAt: now()
                        )
                    )
                    AutonomousLoopAudit.append(
                        goalID: task.goalID,
                        taskID: taskID,
                        eventKind: "autonomy.loop.advisoryCompleted",
                        detail: "Marked advisory task complete.",
                        occurredAt: now(),
                        modelContext: modelContext
                    )
                    continue
                }

                // Tasks with a validation command run the gate even when
                // their mode would otherwise need a provider — the gate
                // is what makes them safe to chain.
                guard let command = task.validationCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !command.isEmpty else {
                    // Mode is non-advisory and no validation command is
                    // attached → kick to approval. The dispatcher will
                    // pick the task up after the user signs off.
                    approvalsSurfaced += 1
                    iterations.append(
                        AutonomousLoopIteration(
                            index: iterations.count,
                            taskID: taskID,
                            taskTitle: task.title,
                            mode: task.mode,
                            status: .approvalRequired,
                            detail: "Non-advisory task without a validation command must run through approval.",
                            validationCommand: nil,
                            validationExitCode: nil,
                            occurredAt: now()
                        )
                    )
                    AutonomousLoopAudit.append(
                        goalID: task.goalID,
                        taskID: taskID,
                        eventKind: "autonomy.loop.approvalRequired",
                        detail: "No validation command; approval required.",
                        occurredAt: now(),
                        modelContext: modelContext
                    )
                    if approvalsSurfaced >= budget.maxApprovalsBeforeHalt {
                        haltReason = .approvalRequired(
                            taskID: taskID,
                            reason: "Approval required: no validation command attached."
                        )
                        break scheduleLoop
                    }
                    continue
                }

                let workingDirectory = projectRootPath ?? ""
                if workingDirectory.isEmpty {
                    iterations.append(
                        AutonomousLoopIteration(
                            index: iterations.count,
                            taskID: taskID,
                            taskTitle: task.title,
                            mode: task.mode,
                            status: .denied,
                            detail: "Missing project root path.",
                            validationCommand: command,
                            validationExitCode: nil,
                            occurredAt: now()
                        )
                    )
                    haltReason = .denied(taskID: taskID, reason: "Missing project root path.")
                    break scheduleLoop
                }
                let result = await validationRunner.run(
                    command: command,
                    workingDirectory: workingDirectory
                )
                let gateAt = now()
                if result.passed {
                    task.status = CoordinationStatus.completed.rawValue
                    task.updatedAt = gateAt
                    completedTaskIDs.append(taskID)
                    consumed.insert(taskID)
                    iterations.append(
                        AutonomousLoopIteration(
                            index: iterations.count,
                            taskID: taskID,
                            taskTitle: task.title,
                            mode: task.mode,
                            status: .validationPassed,
                            detail: "Validation gate passed.",
                            validationCommand: command,
                            validationExitCode: result.exitCode,
                            occurredAt: gateAt
                        )
                    )
                    AutonomousLoopAudit.append(
                        goalID: task.goalID,
                        taskID: taskID,
                        eventKind: "autonomy.loop.validationPassed",
                        detail: "Exit \(result.exitCode)",
                        occurredAt: gateAt,
                        modelContext: modelContext
                    )
                } else {
                    validationFailures += 1
                    task.status = CoordinationStatus.conflict.rawValue
                    task.updatedAt = gateAt
                    iterations.append(
                        AutonomousLoopIteration(
                            index: iterations.count,
                            taskID: taskID,
                            taskTitle: task.title,
                            mode: task.mode,
                            status: .validationFailed,
                            detail: "Validation gate failed; exit \(result.exitCode).",
                            validationCommand: command,
                            validationExitCode: result.exitCode,
                            occurredAt: gateAt
                        )
                    )
                    AutonomousLoopAudit.append(
                        goalID: task.goalID,
                        taskID: taskID,
                        eventKind: "autonomy.loop.validationFailed",
                        detail: "Exit \(result.exitCode)",
                        occurredAt: gateAt,
                        modelContext: modelContext
                    )
                    if validationFailures >= budget.maxValidationFailures {
                        haltReason = .validationFailureCap(failures: validationFailures)
                        break scheduleLoop
                    }
                }
            }
        }

        try? modelContext.save()

        let pendingTaskIDs = orderedTaskIDs.filter { !completedTaskIDs.contains($0) }
        let report = AutonomousLoopRunReport(
            goalID: plan.goalID,
            planID: plan.planID,
            iterations: iterations,
            haltReason: haltReason,
            validationFailureCount: validationFailures,
            approvalSurfaceCount: approvalsSurfaced,
            completedTaskIDs: completedTaskIDs,
            pendingTaskIDs: pendingTaskIDs,
            startedAt: startedAt,
            endedAt: now()
        )
        // Sprint Q.5: persist the report so the autonomy control room
        // and the history view can rebuild what happened across
        // sessions and (via SwiftData CloudKit sync) machines. Errors
        // here are non-fatal — the in-memory report is still returned.
        _ = try? AutonomousLoopPersistence.persistReport(report, modelContext: modelContext, now: now())
        return report
    }
}

@MainActor
enum AutonomousLoopFetcher {
    static func tasks(in modelContext: ModelContext, ids: [String]) -> [AutonomyTaskRecord] {
        let descriptor = FetchDescriptor<AutonomyTaskRecord>()
        guard let all = try? modelContext.fetch(descriptor) else { return [] }
        let set = Set(ids)
        return all.filter { set.contains($0.identifier) }
    }
}

@MainActor
enum AutonomousLoopAudit {
    static func append(
        goalID: String?,
        taskID: String,
        eventKind: String,
        detail: String,
        occurredAt: Date,
        modelContext: ModelContext
    ) {
        modelContext.insert(
            AuditTrailRecord(
                goalID: goalID,
                taskID: taskID,
                eventKind: eventKind,
                detail: detail,
                createdAt: occurredAt
            )
        )
    }
}

@MainActor
enum AutonomousLoopOrder {
    /// Kahn's algorithm over the task dependency JSON so the scheduler
    /// walks tasks in a deterministic, dependency-respecting order. Any
    /// cycle leaves the affected tasks at the end of the queue so the
    /// dependency-deadlock branch in the scheduler can flag them.
    static func topologicalTaskIDs(tasks: [AutonomyTaskRecord]) -> [String] {
        let ids = tasks.map(\.identifier)
        let dependenciesByID = Dictionary(uniqueKeysWithValues: tasks.map { task in
            (
                task.identifier,
                AutonomyPersistence
                    .decodeStrings(task.dependencyIDsJSON)
                    .filter { ids.contains($0) }
            )
        })
        var resolved: [String] = []
        var remaining = Set(ids)

        // Stable iteration order: process by created-at then id so the
        // output is reproducible across runs.
        let stableOrder = tasks
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.identifier < rhs.identifier
                }
                return lhs.createdAt < rhs.createdAt
            }
            .map(\.identifier)

        while !remaining.isEmpty {
            let ready = stableOrder.filter { id in
                guard remaining.contains(id) else { return false }
                let deps = dependenciesByID[id] ?? []
                return deps.allSatisfy { !remaining.contains($0) }
            }
            if ready.isEmpty {
                // Cycle / deadlock — append the rest in stable order so
                // the scheduler can flag the unresolved set.
                resolved.append(contentsOf: stableOrder.filter { remaining.contains($0) })
                remaining.removeAll()
                break
            }
            for id in ready {
                resolved.append(id)
                remaining.remove(id)
            }
        }
        return resolved
    }
}

// MARK: - Sprint Q.5: persist loop reports to SwiftData

/// CloudKit-compatible persistence helpers that round-trip a
/// `AutonomousLoopRunReport` through `AutonomousLoopReportRecord`. The
/// iterations field is stored as JSON so adding fields stays additive
/// (no schema migration when `AutonomousLoopIteration` evolves).
@MainActor
enum AutonomousLoopPersistence {
    static func persistReport(
        _ report: AutonomousLoopRunReport,
        modelContext: ModelContext,
        now: Date = Date()
    ) throws -> AutonomousLoopReportRecord {
        let record = AutonomousLoopReportRecord(
            identifier: "\(report.planID)-\(Int(report.endedAt.timeIntervalSince1970))",
            goalID: report.goalID,
            planID: report.planID,
            haltReasonKind: report.haltReason.kind,
            haltReasonLabel: report.haltReason.label,
            iterationsJSON: encodeIterations(report.iterations),
            validationFailureCount: report.validationFailureCount,
            approvalSurfaceCount: report.approvalSurfaceCount,
            completedTaskIDsJSON: encodeStrings(report.completedTaskIDs),
            pendingTaskIDsJSON: encodeStrings(report.pendingTaskIDs),
            startedAt: report.startedAt,
            endedAt: report.endedAt,
            createdAt: now
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            throw AutonomyExecutionError.saveFailed(error.localizedDescription)
        }
        return record
    }

    static func decodeIterations(_ json: String) -> [AutonomousLoopIteration] {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AutonomousLoopIteration].self, from: data)) ?? []
    }

    static func decodeTaskIDs(_ json: String) -> [String] {
        let data = Data(json.utf8)
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func encodeIterations(_ iterations: [AutonomousLoopIteration]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(iterations),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func encodeStrings(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}

extension AutonomousLoopRunReport {
    /// User-facing chip label used by the loop history panel. Mirrors
    /// `AutonomousLoopReportRecord.haltReasonKind` so persisted and
    /// in-memory reports render identically.
    var haltReasonChipLabel: String {
        switch haltReason {
        case .completed: "Completed"
        case .approvalRequired: "Approval"
        case .denied: "Denied"
        case .validationFailureCap: "Validation"
        case .iterationCap: "Iteration cap"
        case .approvalCap: "Approval cap"
        case .dependencyDeadlock: "Dependency"
        }
    }
}
