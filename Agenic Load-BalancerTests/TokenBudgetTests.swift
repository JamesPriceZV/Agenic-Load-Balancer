//
//  TokenBudgetTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint C focused tests for token-budget estimation and continuation
//  prompt construction.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Token budget")
struct TokenBudgetTests {
    @Test func estimatorClassifiesHighContextPreflight() {
        let estimate = TokenBudgetEstimator.estimatePreflight(
            userPrompt: String(repeating: "prompt ", count: 1_100),
            agentNotesExcerpt: String(repeating: "notes ", count: 1_100),
            workspacePolicy: "Policy",
            projectRootPath: "/tmp/project",
            providerID: "openai.codex",
            contextCompactionEnabled: true,
            thresholdTokens: 3_000
        )

        #expect(estimate.totalInputTokens > 0)
        #expect(estimate.risk == .high || estimate.risk == .overLimit)
        #expect(estimate.needsCompaction)
        #expect(estimate.ledgerLimitWindow.contains("context:"))
    }

    @Test func preflightCompactionPreservesHeadAndTail() {
        let notes = """
        head marker
        \(String(repeating: "middle marker\n", count: 1_000))
        tail marker
        """

        let result = TokenBudgetEstimator.preparePreflightContext(
            userPrompt: "Short prompt",
            agentNotesExcerpt: notes,
            workspacePolicy: "Policy",
            projectRootPath: "/tmp/project",
            providerID: "openai.codex",
            contextCompactionEnabled: true,
            thresholdTokens: 1_200
        )

        #expect(result.didCompact)
        #expect(result.agentNotesExcerpt?.contains("head marker") == true)
        #expect(result.agentNotesExcerpt?.contains("tail marker") == true)
        #expect(result.estimate.totalInputTokens <= 1_200)
    }

    @Test func continuationPromptIncludesRecentOutputAndGoal() {
        let plan = RunPipelineTestsShim.makePlanForTokenBudget(prompt: "Finish the implementation safely.")
        let estimate = TokenBudgetEstimator.estimateRun(
            plan: plan,
            agentNotesExcerpt: "Active claim",
            workspacePolicy: "Policy",
            projectRootPath: nil,
            standardOutput: "last stdout line",
            standardError: "context window exceeded"
        )

        let continuation = TokenBudgetEstimator.makeContinuationPlan(
            plan: plan,
            standardOutput: "last stdout line",
            standardError: "context window exceeded",
            errorMessage: "Provider reported that the request exceeded the available context window.",
            estimate: estimate
        )

        #expect(continuation.prompt.contains("Continue the previous"))
        #expect(continuation.prompt.contains("Finish the implementation safely."))
        #expect(continuation.prompt.contains("last stdout line"))
        #expect(continuation.prompt.contains("context window exceeded"))
        #expect(continuation.estimatedResumeTokens > 0)
    }
}

private enum RunPipelineTestsShim {
    static func makePlanForTokenBudget(prompt: String) -> RunPlan {
        let draft = ProviderCatalog.defaultProfiles[0]
        let snapshot = AgentProviderSnapshot(
            identifier: draft.identifier,
            displayName: draft.displayName,
            binaryName: draft.binaryName,
            installCommand: draft.installCommand,
            verificationCommand: draft.verificationCommand,
            supportedExecutionModes: draft.supportedExecutionModes,
            capabilities: draft.capabilities,
            installedState: .available,
            authState: .authenticated,
            isEnabled: true
        )
        let score = RoutingScoreBreakdown(
            providerID: draft.identifier,
            providerName: draft.displayName,
            mode: .implementation,
            totalScore: 0.85,
            availabilityScore: 1,
            capabilityScore: 0.9,
            limitScore: 0.8,
            accuracyScore: 0.9,
            speedScore: 0.7,
            costScore: 0.85,
            rationale: "Test plan",
            estimatedCostUSD: 0,
            limitImpact: "Low pressure",
            coordinationWarning: ""
        )
        return RunPlan(
            providerSnapshot: snapshot,
            providerID: draft.identifier,
            providerName: draft.displayName,
            prompt: prompt,
            projectID: nil,
            projectName: nil,
            projectRootPath: nil,
            mode: .implementation,
            score: score,
            promptExcerptSyncEnabled: false
        )
    }
}
