//
//  FoundationModelsSafetyAuditTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.6 closeout: executable safety-audit coverage for Foundation
//  Models fallback gates and mutating command-bar approval semantics.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Foundation Models safety audit")
struct FoundationModelsSafetyAuditTests {
    private static var unavailableChecker: StubFoundationModelsAvailabilityChecker {
        StubFoundationModelsAvailabilityChecker(.appleIntelligenceNotEnabled)
    }

    private static var provider: AgentProviderSnapshot {
        AgentProviderSnapshot(
            identifier: "openai.codex",
            displayName: "Codex",
            binaryName: "codex",
            installCommand: "brew install codex",
            verificationCommand: "codex --version",
            supportedExecutionModes: AgentExecutionMode.allCases.map(\.rawValue).joined(separator: ","),
            capabilities: "code-editing,debugging,review,local-workspace",
            installedState: .available,
            authState: .authenticated,
            isEnabled: true
        )
    }

    @Test func unavailableFoundationModelsFactoriesUseFallbacks() async throws {
        let summarizer = RunSummarizerFactory.makeDefault(availabilityChecker: Self.unavailableChecker)
        await #expect(throws: RunSummaryError.self) {
            try await summarizer.summarize(
                input: RunSummaryInput(
                    prompt: "Build",
                    providerID: "apple.foundation-models",
                    providerName: "Foundation Models",
                    mode: .implementation,
                    exitCode: 0,
                    durationSeconds: 1,
                    standardOutput: "",
                    standardError: ""
                )
            )
        }

        let intelligence = AgentNotesIntelligenceFactory.makeDefault(availabilityChecker: Self.unavailableChecker)
        await #expect(throws: AgentNotesIntelligenceError.self) {
            try await intelligence.summarizePreflight(
                agentNotes: "# AgentNotes",
                prompt: "Build",
                mode: .implementation
            )
        }

        let tieBreaker = RoutingTieBreakerFactory.makeDefault(availabilityChecker: Self.unavailableChecker)
        let tieBreak = try await tieBreaker.breakTie(
            input: RoutingTieBreakInput(
                prompt: "Build",
                mode: .implementation,
                candidates: [
                    RoutingScoreBreakdown(
                        providerID: "openai.codex",
                        providerName: "Codex",
                        mode: .implementation,
                        totalScore: 0.9,
                        availabilityScore: 1,
                        capabilityScore: 1,
                        limitScore: 1,
                        accuracyScore: 1,
                        speedScore: 1,
                        costScore: 1,
                        rationale: "top",
                        estimatedCostUSD: 0.01,
                        limitImpact: "low",
                        coordinationWarning: ""
                    ),
                ],
                usage: [],
                accuracy: [],
                reliability: [],
                coordinationEvents: []
            )
        )
        #expect(tieBreak.selectedProviderID == "openai.codex")
        #expect(tieBreak.reason.contains("Apple Intelligence"))
    }

    @Test func commandBarMutatingActionsNeverExecuteWithoutApproval() async {
        let context = CommandBarContext(
            prompt: "Implement the task",
            mode: .implementation,
            projectName: nil,
            projectRootPath: nil,
            providers: [Self.provider]
        )
        let executor = CommandBarActionExecutor()

        let mutatingResults = await [
            executor.dispatchRunDraft(context: context),
            executor.createSnapshotDraft(scope: "current project"),
            executor.reconcileAgentNotesDraft(context: context),
        ]

        #expect(mutatingResults.allSatisfy { $0.approvalRequirement != .none })
        #expect(mutatingResults.contains { $0.approvalRequirement == .userApprovalRequired })
        #expect(mutatingResults.contains { $0.approvalRequirement == .blockedByPolicy })
    }
}
