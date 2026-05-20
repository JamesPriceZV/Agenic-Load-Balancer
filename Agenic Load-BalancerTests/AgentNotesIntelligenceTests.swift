//
//  AgentNotesIntelligenceTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.4 AgentNotes intelligence tests.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Phase 7.4 AgentNotes intelligence")
struct AgentNotesIntelligenceTests {
    @Test func noopPreflightThrowsUnavailableReason() async {
        let intelligence = NoopAgentNotesIntelligence(reason: "Apple Intelligence disabled")

        await #expect(throws: AgentNotesIntelligenceError.unavailable("Apple Intelligence disabled")) {
            _ = try await intelligence.summarizePreflight(
                agentNotes: "# AgentNotes",
                prompt: "Fix tests",
                mode: .repairDebug
            )
        }
    }

    @Test func scriptedPreflightReturnsPromptInjectionText() async throws {
        let intelligence = ScriptedAgentNotesIntelligence(
            summary: AgentNotesPreflightSummary(
                relevantActiveClaims: ["Phase 7.3 command bar is in flight"],
                blockingConflicts: [],
                suggestedClaim: "Claim Phase 7.4 AgentNotes intelligence",
                promptInjectionText: "Relevant active claim: Phase 7.3 command bar is in flight"
            ),
            proposal: AgentNotesMergeProposal(
                mergedContent: "merged",
                retainedLocalLines: [],
                retainedGeneratedLines: [],
                unresolvedConflicts: [],
                explanation: "Merged without conflicts."
            )
        )

        let summary = try await intelligence.summarizePreflight(
            agentNotes: "# AgentNotes",
            prompt: "Wire preflight",
            mode: .implementation
        )
        #expect(summary.promptInjectionText.contains("Phase 7.3"))
        #expect(summary.suggestedClaim == "Claim Phase 7.4 AgentNotes intelligence")
    }

    @Test func scriptedMergeReturnsUnresolvedConflictList() async throws {
        let intelligence = ScriptedAgentNotesIntelligence(
            summary: AgentNotesPreflightSummary(
                relevantActiveClaims: ["Phase 7.2 pending"],
                blockingConflicts: [],
                suggestedClaim: "Claim Phase 7.3",
                promptInjectionText: "Relevant active claim: Phase 7.2 pending"
            ),
            proposal: AgentNotesMergeProposal(
                mergedContent: "merged",
                retainedLocalLines: ["local"],
                retainedGeneratedLines: ["generated"],
                unresolvedConflicts: ["same section edited differently"],
                explanation: "Manual review needed."
            )
        )

        let proposal = try await intelligence.proposeMerge(
            localContent: "local",
            generatedContent: "generated"
        )
        #expect(proposal.unresolvedConflicts == ["same section edited differently"])
    }

    @Test func factoryReturnsNoopWhenFoundationModelsUnavailable() async {
        let intelligence = AgentNotesIntelligenceFactory.makeDefault(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.appleIntelligenceNotEnabled)
        )

        await #expect(throws: AgentNotesIntelligenceError.unavailable(FoundationModelsAvailability.appleIntelligenceNotEnabled.message)) {
            _ = try await intelligence.proposeMerge(localContent: "local", generatedContent: "generated")
        }
    }
}
