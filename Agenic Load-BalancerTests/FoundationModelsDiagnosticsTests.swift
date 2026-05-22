//
//  FoundationModelsDiagnosticsTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint B diagnostics tests for availability gating and live-probe
//  orchestration without requiring Apple Intelligence in CI.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Foundation Models diagnostics")
struct FoundationModelsDiagnosticsTests {
    @Test func unavailableFoundationModelsSkipsLiveProbes() async {
        let runner = FoundationModelsDiagnosticsRunner(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.modelNotReady),
            commandBarResponder: { _, _, _ in
                Issue.record("Command-bar live probe should not run when availability is unavailable.")
                return "unexpected"
            },
            runSummarizer: ScriptedRunSummarizer { _ in
                Issue.record("Run-summary live probe should not run when availability is unavailable.")
                return RunSummary(oneLineDescription: "unexpected", suggestedAccuracyRating: .unrated)
            },
            tieBreaker: ScriptedRoutingTieBreaker(
                result: RoutingTieBreak(
                    selectedProviderID: "unexpected",
                    confidence: 0,
                    reason: "unexpected",
                    cautions: []
                )
            )
        )

        let report = await runner.run()

        #expect(report.availability == .modelNotReady)
        #expect(report.probes.count == FoundationModelsDiagnosticProbeKind.allCases.count)
        #expect(report.probes.first(where: { $0.kind == .availability })?.status == .succeeded)
        #expect(report.probes.filter { $0.status == .skipped }.count == 3)
        #expect(!report.hasFailures)
        #expect(report.statusSummary.contains("skipped"))
    }

    @Test func availableFoundationModelsRunsAllLiveProbes() async {
        let runner = FoundationModelsDiagnosticsRunner(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available),
            commandBarResponder: { prompt, context, _ in
                #expect(prompt.localizedCaseInsensitiveContains("dashboard metrics"))
                #expect(context.providers.count == 2)
                return "Dashboard metrics are readable."
            },
            runSummarizer: ScriptedRunSummarizer(
                constant: RunSummary(
                    filesChanged: [],
                    oneLineDescription: "Diagnostics summary generated.",
                    suggestedAccuracyRating: .correct
                )
            ),
            tieBreaker: ScriptedRoutingTieBreaker(
                result: RoutingTieBreak(
                    selectedProviderID: "diagnostic.alpha",
                    confidence: 0.91,
                    reason: "Best latency and enough accuracy.",
                    cautions: []
                )
            )
        )

        let report = await runner.run()

        #expect(report.availability == .available)
        #expect(report.probes.count == FoundationModelsDiagnosticProbeKind.allCases.count)
        #expect(report.probes.allSatisfy { $0.status == .succeeded })
        #expect(report.statusSummary.contains("All 4 diagnostics succeeded"))
        #expect(report.probes.first(where: { $0.kind == .routingTieBreak })?.detail.contains("diagnostic.alpha") == true)
    }

    @Test func liveProbeFailuresAreClassifiedAndContained() async {
        let runner = FoundationModelsDiagnosticsRunner(
            availabilityChecker: StubFoundationModelsAvailabilityChecker(.available),
            commandBarResponder: { _, _, _ in
                throw CommandBarError.failed("unsupported locale for current model session")
            },
            runSummarizer: ScriptedRunSummarizer(
                constant: RunSummary(
                    oneLineDescription: "Summary still works.",
                    suggestedAccuracyRating: .correct
                )
            ),
            tieBreaker: ScriptedRoutingTieBreaker(
                result: RoutingTieBreak(
                    selectedProviderID: "diagnostic.beta",
                    confidence: 0.78,
                    reason: "Controlled fallback choice.",
                    cautions: []
                )
            )
        )

        let report = await runner.run()
        let commandProbe = report.probes.first { $0.kind == .commandBarMetrics }

        #expect(report.hasFailures)
        #expect(commandProbe?.status == .failed)
        #expect(commandProbe?.summary == "Unsupported locale or language")
        #expect(report.probes.first(where: { $0.kind == .runSummary })?.status == .succeeded)
        #expect(report.probes.first(where: { $0.kind == .routingTieBreak })?.status == .succeeded)
    }
}
