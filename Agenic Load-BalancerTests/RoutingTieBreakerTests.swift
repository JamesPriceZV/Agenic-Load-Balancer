//
//  RoutingTieBreakerTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.5 routing tie-breaker tests.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Phase 7.5 routing tie breaker")
struct RoutingTieBreakerTests {
    @Test func noopPreservesTopDeterministicCandidate() async throws {
        let candidate = Self.candidate(providerID: "openai.codex", totalScore: 0.91)

        let tieBreak = try await NoopRoutingTieBreaker(reason: "Unavailable").breakTie(
            input: RoutingTieBreakInput(
                prompt: "Implement feature",
                mode: .implementation,
                candidates: [candidate],
                usage: [],
                accuracy: [],
                reliability: [],
                coordinationEvents: []
            )
        )

        #expect(tieBreak.selectedProviderID == "openai.codex")
        #expect(tieBreak.confidence == 0)
        #expect(tieBreak.cautions == ["Deterministic score order preserved."])
    }

    @Test func closeScoreDetectorUsesTopWindowAndLimit() {
        let ranked = [
            Self.candidate(providerID: "openai.codex", totalScore: 0.91),
            Self.candidate(providerID: "anthropic.claude-code", totalScore: 0.882),
            Self.candidate(providerID: "apple.foundation-models", totalScore: 0.86),
            Self.candidate(providerID: "deepseek.api", totalScore: 0.88),
        ]

        let candidates = RoutingEngine.closeScoreCandidates(from: ranked, threshold: 0.035, limit: 3)

        #expect(candidates.map(\.providerID) == ["openai.codex", "anthropic.claude-code"])
    }

    @Test func coordinatorSkipsTieBreakerWhenScoresAreNotClose() async {
        let codex = Self.provider(id: "openai.codex", name: "Codex", installedState: .available)
        let missing = Self.provider(id: "deepseek.api", name: "DeepSeek API", installedState: .missing)
        let scripted = ScriptedRoutingTieBreaker(
            result: RoutingTieBreak(
                selectedProviderID: "deepseek.api",
                confidence: 1,
                reason: "Would be wrong if invoked.",
                cautions: []
            )
        )

        let recommendation = await RoutingRecommendationCoordinator(tieBreaker: scripted).recommend(
            prompt: "Implement a dashboard",
            mode: .implementation,
            providers: [codex, missing],
            usage: [],
            accuracy: [],
            reliability: [],
            coordinationEvents: []
        )

        #expect(recommendation.tieBreak == nil)
        #expect(recommendation.selected?.providerID == "openai.codex")
    }

    @Test func coordinatorAppliesScriptedTieBreakForCloseScores() async {
        let codex = Self.provider(id: "openai.codex", name: "Codex")
        let claude = Self.provider(id: "anthropic.claude-code", name: "Claude Code")
        let scripted = ScriptedRoutingTieBreaker(
            result: RoutingTieBreak(
                selectedProviderID: "anthropic.claude-code",
                confidence: 0.82,
                reason: "Prompt asks for careful review and implementation sequencing.",
                cautions: ["Scores were within the close-score threshold."]
            )
        )

        let recommendation = await RoutingRecommendationCoordinator(tieBreaker: scripted).recommend(
            prompt: "Review and implement the next routing feature",
            mode: .implementation,
            providers: [codex, claude],
            usage: [],
            accuracy: [],
            reliability: [],
            coordinationEvents: []
        )

        #expect(recommendation.tieBreak?.selectedProviderID == "anthropic.claude-code")
        #expect(recommendation.selected?.providerID == "anthropic.claude-code")
        #expect(recommendation.ranked.count == 2)
    }

    @Test func coordinatorIgnoresInvalidTieBreakProviderID() async {
        let codex = Self.provider(id: "openai.codex", name: "Codex")
        let claude = Self.provider(id: "anthropic.claude-code", name: "Claude Code")
        let scripted = ScriptedRoutingTieBreaker(
            result: RoutingTieBreak(
                selectedProviderID: "not.configured",
                confidence: 0.98,
                reason: "Invalid provider should not be applied.",
                cautions: []
            )
        )

        let recommendation = await RoutingRecommendationCoordinator(tieBreaker: scripted).recommend(
            prompt: "Implement feature",
            mode: .implementation,
            providers: [codex, claude],
            usage: [],
            accuracy: [],
            reliability: [],
            coordinationEvents: []
        )

        #expect(recommendation.tieBreak == nil)
        #expect(recommendation.selected?.providerID == recommendation.ranked.first?.providerID)
    }

    @Test func factoryFallsBackToNoopWhenFoundationModelsUnavailable() async throws {
        let tieBreaker = RoutingTieBreakerFactory.makeDefault(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.frameworkUnavailable)
        )
        let candidate = Self.candidate(providerID: "openai.codex", totalScore: 0.9)

        let result = try await tieBreaker.breakTie(
            input: RoutingTieBreakInput(
                prompt: "Rank",
                mode: .recommendOnly,
                candidates: [candidate],
                usage: [],
                accuracy: [],
                reliability: [],
                coordinationEvents: []
            )
        )

        #expect(result.selectedProviderID == "openai.codex")
        #expect(result.reason == FoundationModelsAvailability.frameworkUnavailable.message)
    }

    private static func provider(
        id: String,
        name: String,
        installedState: ProviderAvailabilityState = .available
    ) -> AgentProviderSnapshot {
        AgentProviderSnapshot(
            identifier: id,
            displayName: name,
            binaryName: id.components(separatedBy: ".").last ?? id,
            installCommand: "",
            verificationCommand: "",
            supportedExecutionModes: AgentExecutionMode.allCases.map(\.rawValue).joined(separator: ","),
            capabilities: "code-editing,debugging,review,local-workspace",
            installedState: installedState,
            authState: .authenticated,
            isEnabled: true
        )
    }

    private static func candidate(
        providerID: String,
        totalScore: Double,
        providerName: String = "Provider"
    ) -> RoutingScoreBreakdown {
        RoutingScoreBreakdown(
            providerID: providerID,
            providerName: providerName,
            mode: .implementation,
            totalScore: totalScore,
            availabilityScore: 1,
            capabilityScore: 1,
            limitScore: 1,
            accuracyScore: 1,
            speedScore: 1,
            costScore: 1,
            rationale: "Top deterministic score",
            estimatedCostUSD: 0.01,
            limitImpact: "Low pressure",
            coordinationWarning: ""
        )
    }
}
