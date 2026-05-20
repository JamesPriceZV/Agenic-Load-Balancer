//
//  CommandBarActionTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.3 command-bar action tests.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Phase 7.3 command actions")
struct CommandBarActionTests {
    private static func provider(
        id: String = "openai.codex",
        name: String = "Codex"
    ) -> AgentProviderSnapshot {
        AgentProviderSnapshot(
            identifier: id,
            displayName: name,
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

    @Test func formatterIncludesApprovalRequirement() {
        let result = CommandBarActionResult(
            kind: .dispatchRun,
            title: "Approve dispatch to Codex",
            summary: "Prepared implementation run.",
            approvalRequirement: .userApprovalRequired,
            approvalID: "dispatch:openai.codex:test"
        )

        let formatted = CommandBarActionFormatter.format(result)
        #expect(formatted.contains("Approve dispatch to Codex"))
        #expect(formatted.contains("Approval required: dispatch:openai.codex:test"))
    }

    @Test func rankAgentsReturnsTopProvider() async {
        let context = CommandBarContext(
            prompt: "Implement command bar",
            mode: .implementation,
            providers: [Self.provider()]
        )

        let result = await CommandBarActionExecutor().rankAgents(context: context, limit: 3)

        #expect(result.kind == .rankAgents)
        #expect(result.summary.contains("Codex leads"))
        #expect(result.approvalRequirement == .none)
    }

    @Test func dispatchDraftRequiresApproval() async {
        let context = CommandBarContext(
            prompt: "Run the build",
            mode: .testBuild,
            providers: [Self.provider()]
        )

        let result = await CommandBarActionExecutor().dispatchRunDraft(context: context)

        #expect(result.kind == .dispatchRun)
        #expect(result.approvalRequirement == .userApprovalRequired)
        #expect(result.approvalID?.hasPrefix("dispatch:openai.codex:") == true)
    }

    @Test func snapshotDraftRequiresApproval() async {
        let result = await CommandBarActionExecutor().createSnapshotDraft(scope: "full project")

        #expect(result.kind == .createSnapshot)
        #expect(result.approvalRequirement == .userApprovalRequired)
        #expect(result.approvalID?.hasPrefix("snapshot:") == true)
    }

    @Test func dashboardMetricsSummarizeUsageAndAccuracy() async {
        let context = CommandBarContext(
            prompt: "show metrics",
            mode: .recommendOnly,
            providers: [Self.provider()],
            usage: [
                UsageSnapshot(
                    providerID: "openai.codex",
                    callsToday: 2,
                    tokenCountToday: 500,
                    estimatedCostToday: 0.02,
                    sessionSecondsToday: 30,
                    limitPressure: 0.25,
                    refreshDate: nil,
                    averageLatencySeconds: 12,
                    successRate: 0.5
                ),
            ],
            accuracy: [
                AccuracySnapshot(
                    providerID: "openai.codex",
                    totalRatedRuns: 1,
                    averageScore: 1,
                    correctCount: 1,
                    repairCount: 0,
                    failureCount: 0
                ),
            ]
        )

        let result = await CommandBarActionExecutor().readDashboardMetrics(context: context)

        #expect(result.kind == .readDashboardMetrics)
        #expect(result.detailLines.contains { $0.contains("pressure 25%") })
        #expect(result.detailLines.contains { $0.contains("accuracy 100%") })
    }
}
