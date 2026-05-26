//
//  AutonomousLoopSchedulerTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint Q.3: deterministic walks across an autonomy plan plus the
//  bounded halt rules.
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@Suite("Autonomous loop scheduler")
struct AutonomousLoopSchedulerTests {
    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    private static func makePolicy(
        level: AutonomyLevel = .executeApprovedSteps,
        lane: AutonomyTrustLane = .commitPushCheckpoint
    ) -> AutonomyPolicy {
        AutonomyPolicy(
            level: level,
            trustLane: lane,
            allowedRootPaths: ["/tmp/uitest"],
            protectedPathPatterns: [],
            allowedWritePathPatterns: [],
            allowedCommandPrefixes: [],
            validationCommands: ["echo ok"],
            networkAccessAllowed: false,
            requiresApprovalForShell: false,
            requiresApprovalForWrites: false,
            requiresApprovalForCommitPush: false,
            requiresCheckpointBeforeMutation: false,
            requiresSnapshotBeforeMutation: false,
            maxFilesChangedPerTask: 12,
            maxConcurrentRuns: 2,
            maxEstimatedCostUSD: 10.0
        )
    }

    @MainActor
    private static func seedPlan(
        modelContext: ModelContext,
        finalValidationCommand: String?,
        finalMode: AgentExecutionMode = .testBuild,
        startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> PersistedAutonomousPlan {
        let goalID = "loop-goal-1"
        let planID = "loop-plan-1"
        let policyID = "loop-policy-1"
        let inspectID = "loop-task-inspect"
        let planID2 = "loop-task-plan"
        let executeID = "loop-task-execute"
        let validateID = "loop-task-validate"

        let goal = AutonomyGoalRecord(
            identifier: goalID,
            title: "Scheduler fixture",
            goalDescription: "Loop scheduler unit test fixture.",
            createdAt: startedAt,
            updatedAt: startedAt
        )
        let plan = AutonomyPlanRecord(
            identifier: planID,
            goalID: goalID,
            summary: "Loop walk",
            taskIDsJSON: AutonomyPersistence.encodeStrings([inspectID, planID2, executeID, validateID]),
            createdAt: startedAt,
            updatedAt: startedAt
        )
        let policy = AutonomyPolicyRecord(
            identifier: policyID,
            policyJSON: "{}",
            createdAt: startedAt,
            updatedAt: startedAt
        )
        let inspect = AutonomyTaskRecord(
            identifier: inspectID,
            goalID: goalID,
            title: "Inspect",
            detail: "Inspect repo.",
            status: CoordinationStatus.planned.rawValue,
            mode: AgentExecutionMode.readReview.rawValue,
            createdAt: startedAt.addingTimeInterval(1),
            updatedAt: startedAt
        )
        let planTask = AutonomyTaskRecord(
            identifier: planID2,
            goalID: goalID,
            title: "Plan",
            detail: "Plan the work.",
            status: CoordinationStatus.planned.rawValue,
            mode: AgentExecutionMode.planOnly.rawValue,
            dependencyIDsJSON: AutonomyPersistence.encodeStrings([inspectID]),
            createdAt: startedAt.addingTimeInterval(2),
            updatedAt: startedAt
        )
        let execute = AutonomyTaskRecord(
            identifier: executeID,
            goalID: goalID,
            title: "Execute",
            detail: "Execute approved tasks.",
            status: CoordinationStatus.planned.rawValue,
            mode: finalMode.rawValue,
            dependencyIDsJSON: AutonomyPersistence.encodeStrings([planID2]),
            validationCommand: finalValidationCommand,
            createdAt: startedAt.addingTimeInterval(3),
            updatedAt: startedAt
        )
        let validate = AutonomyTaskRecord(
            identifier: validateID,
            goalID: goalID,
            title: "Validate",
            detail: "Validate and checkpoint.",
            status: CoordinationStatus.planned.rawValue,
            mode: AgentExecutionMode.testBuild.rawValue,
            dependencyIDsJSON: AutonomyPersistence.encodeStrings([executeID]),
            validationCommand: "echo validation",
            createdAt: startedAt.addingTimeInterval(4),
            updatedAt: startedAt
        )
        modelContext.insert(goal)
        modelContext.insert(plan)
        modelContext.insert(policy)
        modelContext.insert(inspect)
        modelContext.insert(planTask)
        modelContext.insert(execute)
        modelContext.insert(validate)
        try? modelContext.save()

        return PersistedAutonomousPlan(
            goalID: goalID,
            planID: planID,
            policyID: policyID,
            taskIDsByTitle: [
                "Inspect": inspectID,
                "Plan": planID2,
                "Execute": executeID,
                "Validate": validateID,
            ]
        )
    }

    @MainActor
    @Test func happyPathWalksAdvisoryAndValidatesFinalTask() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_000_500)
        let plan = Self.seedPlan(
            modelContext: context,
            finalValidationCommand: "echo execute"
        )
        let scheduler = AutonomousLoopScheduler(now: { now })
        let validationRunner = ScriptedValidationGateRunner(
            result: ValidationGateResult(
                command: "echo",
                exitCode: 0,
                outputExcerpt: "",
                startedAt: now,
                endedAt: now
            )
        )

        let report = await scheduler.run(
            plan: plan,
            policy: Self.makePolicy(),
            projectRootPath: "/tmp/uitest",
            validationRunner: validationRunner,
            budget: AutonomousLoopBudget(
                maxIterations: 8,
                maxValidationFailures: 1,
                maxApprovalsBeforeHalt: 1
            ),
            modelContext: context
        )

        if case .completed = report.haltReason {} else {
            Issue.record("Expected completed halt; got \(report.haltReason)")
        }
        #expect(report.passed)
        #expect(report.completedTaskIDs.count == 4)
        #expect(report.pendingTaskIDs.isEmpty)
        let statuses = report.iterations.map(\.status)
        #expect(statuses.contains(.completedAdvisory))
        #expect(statuses.contains(.validationPassed))

        let audits = try context.fetch(FetchDescriptor<AuditTrailRecord>())
        #expect(audits.contains { $0.eventKind == "autonomy.loop.advisoryCompleted" })
        #expect(audits.contains { $0.eventKind == "autonomy.loop.validationPassed" })
    }

    @MainActor
    @Test func validationFailureCapHaltsScheduler() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_001_000)
        let plan = Self.seedPlan(
            modelContext: context,
            finalValidationCommand: "echo failing"
        )
        let scheduler = AutonomousLoopScheduler(now: { now })
        let validationRunner = ScriptedValidationGateRunner(
            result: ValidationGateResult(
                command: "echo",
                exitCode: 1,
                outputExcerpt: "fail",
                startedAt: now,
                endedAt: now
            )
        )

        let report = await scheduler.run(
            plan: plan,
            policy: Self.makePolicy(),
            projectRootPath: "/tmp/uitest",
            validationRunner: validationRunner,
            budget: AutonomousLoopBudget(
                maxIterations: 8,
                maxValidationFailures: 1,
                maxApprovalsBeforeHalt: 1
            ),
            modelContext: context
        )

        if case .validationFailureCap(let failures) = report.haltReason {
            #expect(failures == 1)
        } else {
            Issue.record("Expected validationFailureCap halt; got \(report.haltReason)")
        }
        #expect(!report.passed)
        #expect(report.validationFailureCount == 1)
        #expect(report.iterations.last?.status == .validationFailed)
        #expect(report.pendingTaskIDs.contains("loop-task-validate"))
    }

    @MainActor
    @Test func nonAdvisoryTaskWithoutValidationCommandHaltsForApproval() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_001_500)
        let plan = Self.seedPlan(
            modelContext: context,
            finalValidationCommand: nil,
            finalMode: .implementation
        )
        let scheduler = AutonomousLoopScheduler(now: { now })
        let validationRunner = ScriptedValidationGateRunner(
            result: ValidationGateResult(
                command: "echo",
                exitCode: 0,
                outputExcerpt: "",
                startedAt: now,
                endedAt: now
            )
        )

        let report = await scheduler.run(
            plan: plan,
            policy: Self.makePolicy(),
            projectRootPath: "/tmp/uitest",
            validationRunner: validationRunner,
            budget: AutonomousLoopBudget(
                maxIterations: 8,
                maxValidationFailures: 1,
                maxApprovalsBeforeHalt: 1
            ),
            modelContext: context
        )

        if case .approvalRequired(let taskID, let reason) = report.haltReason {
            #expect(taskID == "loop-task-execute")
            #expect(reason.contains("validation command"))
        } else {
            Issue.record("Expected approvalRequired halt; got \(report.haltReason)")
        }
        #expect(report.approvalSurfaceCount == 1)
        #expect(report.pendingTaskIDs.contains("loop-task-execute"))
        #expect(report.pendingTaskIDs.contains("loop-task-validate"))
    }

    @MainActor
    @Test func laneRestrictionDeniesTaskBeyondAllowedModes() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_002_000)
        let plan = Self.seedPlan(
            modelContext: context,
            finalValidationCommand: nil,
            finalMode: .implementation
        )
        let scheduler = AutonomousLoopScheduler(now: { now })
        let validationRunner = ScriptedValidationGateRunner(
            result: ValidationGateResult(
                command: "echo",
                exitCode: 0,
                outputExcerpt: "",
                startedAt: now,
                endedAt: now
            )
        )

        // Test-only lane forbids `.implementation` so the scheduler
        // should hit a denial on the third task.
        let report = await scheduler.run(
            plan: plan,
            policy: Self.makePolicy(lane: .testOnly),
            projectRootPath: "/tmp/uitest",
            validationRunner: validationRunner,
            budget: .default,
            modelContext: context
        )

        if case .denied(let taskID, let reason) = report.haltReason {
            #expect(taskID == "loop-task-execute")
            #expect(reason.contains("Test Only"))
        } else {
            Issue.record("Expected denied halt for implementation under test-only lane; got \(report.haltReason)")
        }
    }

    @MainActor
    @Test func iterationCapHaltsBeforeWalkingAllTasks() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_002_500)
        let plan = Self.seedPlan(
            modelContext: context,
            finalValidationCommand: "echo execute"
        )
        let scheduler = AutonomousLoopScheduler(now: { now })
        let validationRunner = ScriptedValidationGateRunner(
            result: ValidationGateResult(
                command: "echo",
                exitCode: 0,
                outputExcerpt: "",
                startedAt: now,
                endedAt: now
            )
        )

        let report = await scheduler.run(
            plan: plan,
            policy: Self.makePolicy(),
            projectRootPath: "/tmp/uitest",
            validationRunner: validationRunner,
            budget: AutonomousLoopBudget(
                maxIterations: 2,
                maxValidationFailures: 1,
                maxApprovalsBeforeHalt: 1
            ),
            modelContext: context
        )

        if case .iterationCap(let max) = report.haltReason {
            #expect(max == 2)
        } else {
            Issue.record("Expected iterationCap halt; got \(report.haltReason)")
        }
        #expect(report.iterations.count == 2)
        #expect(report.completedTaskIDs.count == 2)
    }

    @MainActor
    @Test func topologicalOrderRespectsDependencies() {
        let now = Date(timeIntervalSince1970: 1_800_003_000)
        let inspect = AutonomyTaskRecord(
            identifier: "a",
            title: "a",
            detail: "",
            createdAt: now.addingTimeInterval(1)
        )
        let plan = AutonomyTaskRecord(
            identifier: "b",
            title: "b",
            detail: "",
            dependencyIDsJSON: AutonomyPersistence.encodeStrings(["a"]),
            createdAt: now.addingTimeInterval(2)
        )
        let execute = AutonomyTaskRecord(
            identifier: "c",
            title: "c",
            detail: "",
            dependencyIDsJSON: AutonomyPersistence.encodeStrings(["b"]),
            createdAt: now.addingTimeInterval(3)
        )
        let validate = AutonomyTaskRecord(
            identifier: "d",
            title: "d",
            detail: "",
            dependencyIDsJSON: AutonomyPersistence.encodeStrings(["c"]),
            createdAt: now.addingTimeInterval(4)
        )

        let ordered = AutonomousLoopOrder.topologicalTaskIDs(
            tasks: [validate, execute, plan, inspect]
        )

        #expect(ordered == ["a", "b", "c", "d"])
    }

    @MainActor
    @Test func topologicalOrderFlagsCyclesInsteadOfHanging() {
        let now = Date(timeIntervalSince1970: 1_800_003_500)
        let a = AutonomyTaskRecord(
            identifier: "a",
            title: "a",
            detail: "",
            dependencyIDsJSON: AutonomyPersistence.encodeStrings(["b"]),
            createdAt: now.addingTimeInterval(1)
        )
        let b = AutonomyTaskRecord(
            identifier: "b",
            title: "b",
            detail: "",
            dependencyIDsJSON: AutonomyPersistence.encodeStrings(["a"]),
            createdAt: now.addingTimeInterval(2)
        )

        let ordered = AutonomousLoopOrder.topologicalTaskIDs(tasks: [a, b])

        // Cycle resolves to stable creation-order so the scheduler can
        // flag the dependency-deadlock branch.
        #expect(ordered == ["a", "b"])
    }
}
