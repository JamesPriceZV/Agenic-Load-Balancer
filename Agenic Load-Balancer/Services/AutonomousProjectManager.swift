//
//  AutonomousProjectManager.swift
//  Agenic Load-Balancer
//
//  Phase 7.6: safe goal-to-plan foundation for autonomous project work.
//

import Foundation

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
