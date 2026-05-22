//
//  AutonomousProjectManagerTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.6 autonomous project manager tests.
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@MainActor
@Suite("Phase 7.6 autonomous project manager")
struct AutonomousProjectManagerTests {
    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "AutonomousProjectManagerTests-\(UUID().uuidString)",
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    private static func request(policy: AutonomyPolicy = .defaultSafe) -> AutonomousGoalRequest {
        AutonomousGoalRequest(
            title: "Ship command bar",
            goalDescription: "Build Phase 7.3",
            projectID: "project-1",
            projectRootPath: "/repo",
            autonomyPolicy: policy
        )
    }

    @Test func deterministicPlannerCreatesInspectionFirst() async throws {
        let request = Self.request()

        let draft = try await AutonomousProjectManager().draftPlan(request: request)

        #expect(draft.tasks.first?.title == "Inspect repo contract")
        #expect(draft.tasks.contains { $0.validationCommand?.contains("xcodebuild") == true })
    }

    @Test func deterministicPlannerUsesTrustLaneValidationCommand() async throws {
        let policy = AutonomyTrustLaneTemplate(
            lane: .smallFileEdits,
            rootPath: "/repo",
            level: .proposeActions
        ).policy
        let request = Self.request(policy: policy)

        let draft = try await AutonomousProjectManager().draftPlan(request: request)

        let validationTask = try #require(draft.tasks.first { $0.title == "Validate and checkpoint" })
        #expect(validationTask.validationCommand == policy.validationCommands.first)
        #expect(validationTask.validationCommand?.contains("arch=arm64") == true)
    }

    @Test func managerRequiresApprovalForImplementationUnderDefaultPolicy() async throws {
        let request = Self.request()
        let task = AutonomousTaskDraft(
            title: "Execute",
            detail: "Edit files",
            mode: .implementation,
            dependencyTitles: [],
            validationCommand: nil
        )

        let decision = await AutonomousProjectManager().evaluate(
            task: task,
            request: request,
            estimatedCostUSD: 0.01
        )

        #expect(decision == .requiresApproval("Shell-backed execution requires approval."))
    }

    @Test func persistenceCreatesGoalPlanTasksPolicyAndAuditRecords() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let request = Self.request()
        let draft = try await AutonomousProjectManager().draftPlan(request: request)

        let persisted = try AutonomyPersistence.persistDraftPlan(
            request: request,
            draft: draft,
            modelContext: context
        )

        let goals = try context.fetch(FetchDescriptor<AutonomyGoalRecord>())
        let plans = try context.fetch(FetchDescriptor<AutonomyPlanRecord>())
        let tasks = try context.fetch(FetchDescriptor<AutonomyTaskRecord>())
        let policies = try context.fetch(FetchDescriptor<AutonomyPolicyRecord>())
        let audits = try context.fetch(FetchDescriptor<AuditTrailRecord>())

        #expect(goals.count == 1)
        #expect(plans.count == 1)
        #expect(tasks.count == draft.tasks.count)
        #expect(policies.count == 1)
        #expect(audits.contains { $0.eventKind == "autonomy.plan.persisted" })
        #expect(persisted.taskIDsByTitle["Create implementation plan"] != nil)

        let planTaskIDs = AutonomyPersistence.decodeStrings(plans[0].taskIDsJSON)
        #expect(planTaskIDs.count == draft.tasks.count)
        let implementation = try #require(tasks.first { $0.title == "Execute approved implementation" })
        #expect(AutonomyPersistence.decodeStrings(implementation.dependencyIDsJSON).count == 1)
    }

    @Test func validationGatePersistsResultAndCompletesTask() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let request = Self.request()
        let draft = try await AutonomousProjectManager().draftPlan(request: request)
        let persisted = try AutonomyPersistence.persistDraftPlan(
            request: request,
            draft: draft,
            modelContext: context
        )
        let taskID = try #require(persisted.taskIDsByTitle["Validate and checkpoint"])
        let result = ValidationGateResult(
            command: "echo ok",
            exitCode: 0,
            outputExcerpt: "ok",
            startedAt: Date(),
            endedAt: Date()
        )

        let returned = try await AutonomyPersistence.runValidationGate(
            taskID: taskID,
            command: "echo ok",
            workingDirectory: "/repo",
            policy: request.autonomyPolicy,
            runner: ScriptedValidationGateRunner(result: result),
            modelContext: context
        )

        #expect(returned.passed)
        let gates = try context.fetch(FetchDescriptor<ValidationGateRecord>())
        #expect(gates.first?.status == "passed")
        let task = try #require(try context.fetch(FetchDescriptor<AutonomyTaskRecord>()).first { $0.identifier == taskID })
        #expect(task.status == CoordinationStatus.completed.rawValue)
        let audits = try context.fetch(FetchDescriptor<AuditTrailRecord>())
        #expect(audits.contains { $0.eventKind == "autonomy.validation.passed" })
    }
}
