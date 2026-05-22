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

    @Test func trustLaneTemplateSetsRootCommandsAndValidationGate() {
        let template = AutonomyTrustLaneTemplate(
            lane: .smallFileEdits,
            rootPath: "/repo",
            level: .proposeActions
        )
        let policy = template.policy

        #expect(policy.trustLane == .smallFileEdits)
        #expect(policy.allowedRootPaths == ["/repo"])
        #expect(policy.allowedCommandPrefixes.contains("git diff --check"))
        #expect(policy.validationCommands.first?.contains("platform=macOS,arch=arm64") == true)
        #expect(policy.requiresCheckpointBeforeMutation)
    }

    @Test func mutationLaneRequiresRollbackEvidenceBeforeImplementation() {
        let policy = AutonomyTrustLaneTemplate(
            lane: .smallFileEdits,
            rootPath: "/repo",
            level: .proposeActions
        ).policy

        let decision = AutonomyPolicyEvaluator().evaluateRun(
            mode: .implementation,
            estimatedCostUSD: 0.01,
            policy: policy,
            evidence: AutonomySafetyEvidence()
        )

        #expect(decision == .denied("Create a snapshot or git checkpoint before using Small File Edits."))
    }

    @Test func mutationLaneAllowsImplementationAfterSnapshotButStillRequiresApproval() {
        let policy = AutonomyTrustLaneTemplate(
            lane: .smallFileEdits,
            rootPath: "/repo",
            level: .proposeActions
        ).policy

        let decision = AutonomyPolicyEvaluator().evaluateRun(
            mode: .implementation,
            estimatedCostUSD: 0.01,
            policy: policy,
            evidence: AutonomySafetyEvidence(hasRecentSnapshot: true)
        )

        #expect(decision == .requiresApproval("Shell-backed execution requires approval."))
    }

    @Test func docsOnlyLaneRejectsSourceWrites() {
        let policy = AutonomyTrustLaneTemplate(
            lane: .docsOnlyEdits,
            rootPath: "/repo",
            level: .proposeActions
        ).policy

        let decision = AutonomyPolicyEvaluator().evaluateWrite(
            path: "/repo/Agenic Load-Balancer/Services/AutonomyPolicy.swift",
            policy: policy
        )

        #expect(decision == .requiresApproval("Path matches protected pattern."))
    }

    @Test func commandOutsideLaneAllowlistIsDenied() {
        let policy = AutonomyTrustLaneTemplate(
            lane: .testOnly,
            rootPath: "/repo",
            level: .proposeActions
        ).policy

        let decision = AutonomyPolicyEvaluator().evaluateCommand(
            "rm -rf /repo/tmp",
            policy: policy
        )

        #expect(decision == .denied("Command is outside the Test Only allowlist."))
    }

    @Test func safetyReviewExplainsStopReason() {
        let policy = AutonomyTrustLaneTemplate(
            lane: .planOnly,
            rootPath: "/repo",
            level: .proposeActions
        ).policy

        let review = AutonomyPolicyEvaluator().safetyReview(
            title: "Execute",
            mode: .implementation,
            estimatedCostUSD: 0.01,
            policy: policy,
            evidence: AutonomySafetyEvidence()
        )

        #expect(review.isBlocked)
        #expect(review.stopReason == "Plan Only lane does not allow Implement runs.")
        #expect(review.reasons.contains { $0.contains("Allowed roots: /repo") })
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
