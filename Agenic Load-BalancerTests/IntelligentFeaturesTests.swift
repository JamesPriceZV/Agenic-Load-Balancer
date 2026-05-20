//
//  IntelligentFeaturesTests.swift
//  Agenic Load-BalancerTests
//
//  Created by Claude on 5/20/26.
//
//  Phases 7.2 – 7.5: unit tests for structured outcome classification,
//  the command-bar coordinator, AgentNotes summarisation/merge, and the
//  routing tie-breaker. All tests use stub collaborators so they never
//  touch real Foundation Models / Apple Intelligence.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

// MARK: - Phase 7.2 — Structured outcome classification

@Suite("Phase 7.2 — Outcome classification")
struct OutcomeClassificationTests {

    @Test func stubClassifierReturnsConfiguredResult() async {
        let expected = RunClassificationResult(
            filesChanged: ["Sources/Foo.swift", "Tests/FooTests.swift"],
            testsPassed: 5,
            testsFailed: 0,
            oneLineDescription: "Added Foo feature with full test coverage.",
            suggestedAccuracyRating: .correct
        )
        let stub = StubOutcomeClassifier(result: expected)
        let result = await stub.classify(stdout: "All tests passed.", stderr: "", prompt: "add foo")
        #expect(result != nil)
        #expect(result?.filesChanged == ["Sources/Foo.swift", "Tests/FooTests.swift"])
        #expect(result?.testsPassed == 5)
        #expect(result?.testsFailed == 0)
        #expect(result?.suggestedAccuracyRating == .correct)
        #expect(result?.oneLineDescription == "Added Foo feature with full test coverage.")
    }

    @Test func stubClassifierReturnsNilWhenConfigured() async {
        let stub = StubOutcomeClassifier(result: nil)
        let result = await stub.classify(stdout: "some output", stderr: "", prompt: "fix bug")
        #expect(result == nil)
    }

    @Test func runClassificationResultAccuracyRatingsMapToKnownValues() {
        let cases: [(AccuracyRating)] = [
            .correct, .minorFixNeeded, .debugNeeded, .recodeNeeded, .brokeBuildOrTests
        ]
        for rating in cases {
            let r = RunClassificationResult(
                filesChanged: [],
                testsPassed: 0,
                testsFailed: 0,
                oneLineDescription: "test",
                suggestedAccuracyRating: rating
            )
            #expect(AccuracyRating(rawValue: r.suggestedAccuracyRating.rawValue) == rating)
        }
    }

    @Test func runClassificationResultIsEquatable() {
        let a = RunClassificationResult(
            filesChanged: ["a.swift"],
            testsPassed: 1,
            testsFailed: 0,
            oneLineDescription: "desc",
            suggestedAccuracyRating: .correct
        )
        let b = RunClassificationResult(
            filesChanged: ["a.swift"],
            testsPassed: 1,
            testsFailed: 0,
            oneLineDescription: "desc",
            suggestedAccuracyRating: .correct
        )
        #expect(a == b)
    }

    @Test func liveClassifierReturnsNilWhenAvailabilityIsOff() async {
        let classifier = LiveOutcomeClassifier(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.appleIntelligenceNotEnabled)
        )
        let result = await classifier.classify(
            stdout: "Built successfully.",
            stderr: "",
            prompt: "implement feature"
        )
        #expect(result == nil)
    }

    @Test func liveClassifierReturnsNilForEmptyStdout() async {
        let classifier = LiveOutcomeClassifier(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available)
        )
        let result = await classifier.classify(stdout: "", stderr: "", prompt: "test")
        #expect(result == nil)
    }
}

// MARK: - Phase 7.3 — Command bar

@MainActor
@Suite("Phase 7.3 — Command bar coordinator")
struct CommandBarTests {

    @Test func coordinatorInitializesToIdleState() {
        let coordinator = CommandBarCoordinator()
        #expect(!coordinator.isGenerating)
        #expect(coordinator.response.isEmpty)
        #expect(coordinator.question.isEmpty)
        #expect(coordinator.errorMessage == nil)
    }

    @Test func cancelWhileIdleDoesNotCrash() {
        let coordinator = CommandBarCoordinator()
        coordinator.cancel()
        #expect(!coordinator.isGenerating)
        #expect(coordinator.response.isEmpty)
    }

    @Test func resetClearsAllState() {
        let coordinator = CommandBarCoordinator()
        coordinator.reset()
        #expect(coordinator.question.isEmpty)
        #expect(coordinator.response.isEmpty)
        #expect(coordinator.errorMessage == nil)
        #expect(!coordinator.isGenerating)
    }

    @Test func askWithEmptyQuestionDoesNotStartGeneration() async {
        let coordinator = CommandBarCoordinator()
        coordinator.question = "   "
        coordinator.ask(providers: [], usage: [], accuracy: [])
        #expect(!coordinator.isGenerating)
    }
}

// MARK: - Phase 7.4 — AgentNotes summarisation + merge proposal

@Suite("Phase 7.4 — AgentNotes intelligent preflight")
struct AgentNotesSummarizationTests {

    @Test func stubSummarizerReturnsConfiguredSummary() async {
        let stub = StubAgentNotesSummarizer(result: "• Phase 7.2 in progress\n• No blockers")
        let result = await stub.summarize(content: "long notes content", forPrompt: "add feature")
        #expect(result == "• Phase 7.2 in progress\n• No blockers")
    }

    @Test func stubSummarizerReturnsNilWhenNotProvided() async {
        let stub = StubAgentNotesSummarizer(result: nil)
        let result = await stub.summarize(content: "any content", forPrompt: "any prompt")
        #expect(result == nil)
    }

    @Test func liveSummarizerReturnsNilWhenUnavailable() async {
        let summarizer = LiveAgentNotesSummarizer(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.deviceNotEligible)
        )
        let result = await summarizer.summarize(content: "# AgentNotes\nSome content", forPrompt: "add foo")
        #expect(result == nil)
    }

    @Test func liveSummarizerReturnsNilForEmptyContent() async {
        let summarizer = LiveAgentNotesSummarizer(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available)
        )
        let result = await summarizer.summarize(content: "", forPrompt: "any")
        #expect(result == nil)
    }

    @Test func stubMergeProposerReturnsConfiguredProposal() async {
        let stub = StubAgentNotesMergeProposer(result: "# Merged AgentNotes\n\nMerged content.")
        let result = await stub.proposeMerge(onDisk: "old version", generated: "new version")
        #expect(result?.contains("Merged") == true)
    }

    @Test func stubMergeProposerReturnsNilWhenNotProvided() async {
        let stub = StubAgentNotesMergeProposer(result: nil)
        let result = await stub.proposeMerge(onDisk: "a", generated: "b")
        #expect(result == nil)
    }

    @Test func liveMergeProposerReturnsNilWhenUnavailable() async {
        let proposer = LiveAgentNotesMergeProposer(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.modelNotReady)
        )
        let result = await proposer.proposeMerge(
            onDisk: "## On-disk content",
            generated: "## Generated content"
        )
        #expect(result == nil)
    }
}

// MARK: - Phase 7.5 — Routing tie-breaker

@Suite("Phase 7.5 — Routing tie-breaker")
struct RoutingTieBreakerTests {

    private static func makeCandidate(
        id: String,
        name: String,
        score: Double
    ) -> RoutingScoreBreakdown {
        RoutingScoreBreakdown(
            providerID: id,
            providerName: name,
            mode: .implementation,
            totalScore: score,
            availabilityScore: 1.0,
            capabilityScore: 0.9,
            limitScore: 0.85,
            accuracyScore: 0.8,
            speedScore: 0.75,
            costScore: 0.7,
            rationale: "Strong candidate",
            estimatedCostUSD: 0.001,
            limitImpact: "Low",
            coordinationWarning: ""
        )
    }

    @Test func stubTieBreakerReturnsConfiguredResult() async {
        let expected = RoutingTieBreakResult(
            preferredProviderID: "openai.codex",
            reasoning: "Codex has stronger code-editing for this refactor task."
        )
        let stub = StubRoutingTieBreaker(result: expected)
        let candidates = [
            Self.makeCandidate(id: "openai.codex", name: "OpenAI Codex", score: 0.82),
            Self.makeCandidate(id: "anthropic.claude", name: "Claude Code", score: 0.79),
        ]
        let result = await stub.tieBreak(prompt: "refactor the sorting algorithm", candidates: candidates)
        #expect(result?.preferredProviderID == "openai.codex")
        #expect(result?.reasoning.contains("code-editing") == true)
    }

    @Test func stubTieBreakerReturnsNilWhenConfiguredNil() async {
        let stub = StubRoutingTieBreaker(result: nil)
        let candidates = [
            Self.makeCandidate(id: "provider.a", name: "Provider A", score: 0.80),
            Self.makeCandidate(id: "provider.b", name: "Provider B", score: 0.78),
        ]
        let result = await stub.tieBreak(prompt: "any task", candidates: candidates)
        #expect(result == nil)
    }

    @Test func routingTieBreakResultIsEquatable() {
        let a = RoutingTieBreakResult(preferredProviderID: "openai.codex", reasoning: "Fast and accurate.")
        let b = RoutingTieBreakResult(preferredProviderID: "openai.codex", reasoning: "Fast and accurate.")
        #expect(a == b)
    }

    @Test func liveTieBreakerReturnsNilWhenUnavailable() async {
        let breaker = LiveRoutingTieBreaker(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.appleIntelligenceNotEnabled)
        )
        let candidates = [
            Self.makeCandidate(id: "a", name: "A", score: 0.81),
            Self.makeCandidate(id: "b", name: "B", score: 0.80),
        ]
        let result = await breaker.tieBreak(prompt: "test", candidates: candidates)
        #expect(result == nil)
    }

    @Test func liveTieBreakerReturnsNilForFewerThanTwoCandidates() async {
        let breaker = LiveRoutingTieBreaker(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available)
        )
        let result = await breaker.tieBreak(
            prompt: "any",
            candidates: [Self.makeCandidate(id: "only", name: "Only", score: 0.90)]
        )
        #expect(result == nil)
    }
}
