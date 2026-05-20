//
//  AutonomyPolicyTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.6 autonomy policy and schema tests.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Phase 7.6 autonomy policy")
struct AutonomyPolicyTests {
    @Test func deniesWritesOutsideAllowedRoot() {
        let policy = AutonomyPolicy.defaultSafe
        let decision = AutonomyPolicyEvaluator().evaluateWrite(path: "/tmp/file.swift", policy: policy)

        #expect(decision == .denied("Path is outside allowed project roots."))
    }

    @Test func protectedPathRequiresApprovalInsideAllowedRoot() {
        var policy = AutonomyPolicy.defaultSafe
        policy.allowedRootPaths = ["/repo"]

        let decision = AutonomyPolicyEvaluator().evaluateWrite(path: "/repo/.git/config", policy: policy)

        #expect(decision == .requiresApproval("Path matches protected pattern."))
    }

    @Test func commitPushRequiresApprovalByDefault() {
        var policy = AutonomyPolicy.defaultSafe
        policy.allowedRootPaths = ["/repo"]

        let decision = AutonomyPolicyEvaluator().evaluateRun(
            mode: .commitPushCheckpoint,
            estimatedCostUSD: 0.01,
            policy: policy
        )

        #expect(decision == .requiresApproval("Commit and push require approval."))
    }

    @Test func overBudgetRunIsDenied() {
        let decision = AutonomyPolicyEvaluator().evaluateRun(
            mode: .implementation,
            estimatedCostUSD: 2,
            policy: .defaultSafe
        )

        #expect(decision == .denied("Estimated cost exceeds policy budget."))
    }

    @Test func observeOnlyDeniesDispatch() {
        var policy = AutonomyPolicy.defaultSafe
        policy.level = .observeOnly

        let decision = AutonomyPolicyEvaluator().evaluateRun(
            mode: .implementation,
            estimatedCostUSD: 0.01,
            policy: policy
        )

        #expect(decision == .denied("Observe-only autonomy cannot dispatch runs."))
    }

    @Test func autonomyModelsAreRegisteredInSchema() {
        let names = AgenicDataModel.models.map { String(describing: $0) }

        #expect(names.contains("AutonomyGoalRecord"))
        #expect(names.contains("AutonomyTaskRecord"))
        #expect(names.contains("AutonomyPolicyRecord"))
        #expect(names.contains("MachinePeerRecord"))
        #expect(names.contains("AutonomyOperationRecord"))
        #expect(names.contains("ConflictResolutionRecord"))
        #expect(names.contains("ValidationGateRecord"))
        #expect(names.contains("AuditTrailRecord"))
    }
}
