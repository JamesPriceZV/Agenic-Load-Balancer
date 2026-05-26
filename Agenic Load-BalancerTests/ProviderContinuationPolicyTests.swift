//
//  ProviderContinuationPolicyTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint O.1: per-provider continuation policy + chain-aware
//  `prepareContinuation` decision logic. These tests exercise the
//  deterministic surface that the run dispatcher relies on, so the
//  approval sheet's "why this is safe" text and the chain-depth cap stay
//  honest as new providers get added to the catalog.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Provider continuation policy")
struct ProviderContinuationPolicyTests {
    @Test func codexPolicyAllowsBoundedAutoResume() {
        let policy = ProviderContinuationPolicy.defaultPolicy(for: "openai.codex")
        #expect(policy.allowsAutomaticResume)
        #expect(policy.maxChainDepth == 3)
        #expect(policy.eligibleTriggers.contains(.contextOverflow))
        #expect(policy.permitsContinuation(at: 0, trigger: .contextOverflow))
        #expect(policy.permitsContinuation(at: 2, trigger: .contextOverflow))
        #expect(!policy.permitsContinuation(at: 3, trigger: .contextOverflow))
    }

    @Test func foundationModelsPolicyIsApprovalGatedAndShallow() {
        let policy = ProviderContinuationPolicy.defaultPolicy(for: "apple.foundation-models")
        #expect(!policy.allowsAutomaticResume)
        #expect(policy.maxChainDepth == 1)
        #expect(policy.eligibleTriggers == [.contextOverflow])
        #expect(!policy.permitsContinuation(at: 0, trigger: .quotaOrRateLimit))
    }

    @Test func xcodeBuildMCPRefusesContinuation() {
        let policy = ProviderContinuationPolicy.defaultPolicy(for: "xcodebuildmcp.source")
        #expect(policy.maxChainDepth == 0)
        #expect(policy.eligibleTriggers.isEmpty)
        #expect(!policy.permitsContinuation(at: 0, trigger: .contextOverflow))
    }

    @Test func unknownProviderFallsBackToConservativeRule() {
        let policy = ProviderContinuationPolicy.defaultPolicy(for: "brand.new.cli")
        #expect(!policy.allowsAutomaticResume)
        #expect(policy.eligibleTriggers == [.contextOverflow])
        #expect(policy.maxChainDepth == 2)
    }

    @Test func failureClassifierMapsKnownMessages() {
        #expect(ProviderFailureClassifier.categorize(errorMessage: nil) == .unknown)
        #expect(ProviderFailureClassifier.categorize(
            errorMessage: "Provider reported that the request exceeded the available context window."
        ) == .contextOverflow)
        #expect(ProviderFailureClassifier.categorize(
            errorMessage: "Provider reported a quota or rate-limit failure."
        ) == .quotaOrRateLimit)
        #expect(ProviderFailureClassifier.categorize(
            errorMessage: "Provider reported a failed run in its structured output."
        ) == .structuredFailure)
        #expect(ProviderFailureClassifier.categorize(
            errorMessage: "Provider reported an inner command failure with exit code 2."
        ) == .nestedNonZeroExit)
    }

    @Test func prepareContinuationRefusesIneligibleTrigger() {
        let plan = ContinuationFixtures.plan(providerID: "github.copilot-cli")
        let estimate = ContinuationFixtures.estimate(for: plan)
        let policy = ProviderContinuationPolicy.defaultPolicy(for: plan.providerID)

        let decision = TokenBudgetEstimator.prepareContinuation(
            plan: plan,
            parentRunID: "run-1",
            parentChainDepth: 0,
            triggerCategory: .quotaOrRateLimit,
            errorMessage: "Provider reported a quota or rate-limit failure.",
            standardOutput: "",
            standardError: "",
            estimate: estimate,
            policy: policy
        )

        switch decision {
        case .notEligible(let reason):
            #expect(reason.contains("Quota or rate limit"))
        case .prepared:
            Issue.record("Expected notEligible decision for Copilot CLI quota trigger.")
        }
    }

    @Test func prepareContinuationCapsAtPolicyChainDepth() {
        let plan = ContinuationFixtures.plan(providerID: "openai.codex")
        let estimate = ContinuationFixtures.estimate(for: plan)
        let policy = ProviderContinuationPolicy.defaultPolicy(for: plan.providerID)

        let decision = TokenBudgetEstimator.prepareContinuation(
            plan: plan,
            parentRunID: "run-codex-3",
            parentChainDepth: policy.maxChainDepth, // would make next depth = cap + 1
            triggerCategory: .contextOverflow,
            errorMessage: "Provider reported that the request exceeded the available context window.",
            standardOutput: "tail",
            standardError: "tail",
            estimate: estimate,
            policy: policy
        )

        switch decision {
        case .notEligible(let reason):
            #expect(reason.contains("exceed policy cap"))
        case .prepared:
            Issue.record("Expected notEligible decision when parent already at policy cap.")
        }
    }

    @Test func prepareContinuationPreparesAutoResumeForCodex() {
        let plan = ContinuationFixtures.plan(providerID: "openai.codex")
        let estimate = ContinuationFixtures.estimate(for: plan)
        let policy = ProviderContinuationPolicy.defaultPolicy(for: plan.providerID)

        let decision = TokenBudgetEstimator.prepareContinuation(
            plan: plan,
            parentRunID: "run-codex-1",
            parentChainDepth: 0,
            triggerCategory: .contextOverflow,
            errorMessage: "Provider reported that the request exceeded the available context window.",
            standardOutput: "last stdout line",
            standardError: "context window exceeded",
            estimate: estimate,
            policy: policy
        )

        switch decision {
        case .prepared(let continuation, let requiresApproval, let appliedPolicy):
            #expect(!requiresApproval)
            #expect(continuation.chainDepth == 1)
            #expect(continuation.parentRunID == "run-codex-1")
            #expect(continuation.triggerCategory == ContinuationTriggerCategory.contextOverflow.rawValue)
            #expect(continuation.prompt.contains("Continue the previous"))
            #expect(continuation.prompt.contains(ContinuationTriggerCategory.contextOverflow.label))
            #expect(appliedPolicy.providerID == plan.providerID)
        case .notEligible(let reason):
            Issue.record("Expected prepared decision for Codex first resume; got notEligible: \(reason)")
        }
    }

    @Test func workspaceSourceSummarizerSkipsBinariesAndRespectsCap() throws {
        let temporaryRoot = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let textFile = temporaryRoot.appendingPathComponent("Sample.swift")
        try """
        import Foundation
        struct Sample {
            let value: Int
            func describe() -> String { "value=\\(value)" }
        }
        """.write(to: textFile, atomically: true, encoding: .utf8)

        let binaryFile = temporaryRoot.appendingPathComponent("Sample.bin")
        let binaryData = Data((0..<512).map { UInt8($0 % 256) })
        try binaryData.write(to: binaryFile)

        let skippedDir = temporaryRoot.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: skippedDir, withIntermediateDirectories: true)
        try "junk".write(
            to: skippedDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        let context = WorkspaceSourceSummarizer.summarize(
            projectRootPath: temporaryRoot.path,
            targetTotalTokens: 800
        )

        #expect(context.excerpts.count == 1)
        #expect(context.excerpts.first?.relativePath == "Sample.swift")
        #expect(context.formattedPromptFragment.contains("Sample.swift"))
        #expect(context.formattedPromptFragment.contains("struct Sample"))
    }
}

enum ContinuationFixtures {
    static func plan(providerID: String) -> RunPlan {
        let draft = ProviderCatalog.defaultProfiles[0]
        let snapshot = AgentProviderSnapshot(
            identifier: providerID,
            displayName: providerID,
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
            providerID: providerID,
            providerName: providerID,
            mode: .implementation,
            totalScore: 0.7,
            availabilityScore: 1,
            capabilityScore: 0.8,
            limitScore: 0.8,
            accuracyScore: 0.8,
            speedScore: 0.7,
            costScore: 0.7,
            rationale: "continuation fixture",
            estimatedCostUSD: 0,
            limitImpact: "Low pressure",
            coordinationWarning: ""
        )
        return RunPlan(
            providerSnapshot: snapshot,
            providerID: providerID,
            providerName: providerID,
            prompt: "Finish the implementation safely.",
            projectID: nil,
            projectName: nil,
            projectRootPath: nil,
            mode: .implementation,
            score: score,
            promptExcerptSyncEnabled: false
        )
    }

    static func estimate(for plan: RunPlan) -> TokenBudgetEstimate {
        TokenBudgetEstimator.estimateRun(
            plan: plan,
            agentNotesExcerpt: "Active claim",
            workspacePolicy: "Policy",
            projectRootPath: nil,
            standardOutput: "last stdout line",
            standardError: "context window exceeded"
        )
    }
}
