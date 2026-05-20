//
//  AutonomousProjectManagerTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.6 autonomous project manager tests.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Phase 7.6 autonomous project manager")
struct AutonomousProjectManagerTests {
    @Test func deterministicPlannerCreatesInspectionFirst() async throws {
        let request = AutonomousGoalRequest(
            title: "Ship command bar",
            goalDescription: "Build Phase 7.3",
            projectID: "project-1",
            projectRootPath: "/repo",
            autonomyPolicy: .defaultSafe
        )

        let draft = try await AutonomousProjectManager().draftPlan(request: request)

        #expect(draft.tasks.first?.title == "Inspect repo contract")
        #expect(draft.tasks.contains { $0.validationCommand?.contains("xcodebuild") == true })
    }

    @Test func managerRequiresApprovalForImplementationUnderDefaultPolicy() async throws {
        let request = AutonomousGoalRequest(
            title: "Ship command bar",
            goalDescription: "Build Phase 7.3",
            projectID: "project-1",
            projectRootPath: "/repo",
            autonomyPolicy: .defaultSafe
        )
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
}
