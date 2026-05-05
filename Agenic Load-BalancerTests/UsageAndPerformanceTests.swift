//
//  UsageAndPerformanceTests.swift
//  Agenic Load-BalancerTests
//
//  Created by Claude on 5/5/26.
//
//  Phase 4: tests for the usage policy and performance history builders.
//  These exercise the math directly with controlled inputs so they don't
//  depend on the Date() clock or SwiftData fetch order.
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@MainActor
@Suite("Usage & performance pipeline")
struct UsageAndPerformanceTests {
    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "UsagePerfTests-\(UUID().uuidString)",
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    // MARK: UsageLimitPolicy

    @Test func defaultPolicySeedsKnownProviders() {
        let policy = UsageLimitPolicy.default
        let codex = policy.quota(forProvider: "openai.codex")
        #expect(codex.providerID == "openai.codex")
        #expect(codex.maxCallsPerWindow > 0)
        #expect(codex.refreshWindow == .daily)
    }

    @Test func defaultPolicyFallsBackForUnknownProvider() {
        let policy = UsageLimitPolicy.default
        let unknown = policy.quota(forProvider: "totally.unseen.provider")
        #expect(unknown.providerID == "default")
        #expect(unknown.maxCallsPerWindow > 0)
    }

    @Test func pressureScalesLinearlyWithCalls() {
        let policy = UsageLimitPolicy.default
        let halfway = policy.computePressure(
            forProvider: "openai.codex",
            calls: 100,
            tokens: 0,
            cost: 0,
            sessionSeconds: 0
        )
        #expect(abs(halfway.callsUsage - 0.5) < 0.001)
        // Aggregate at 50% calls only ≈ 0.5 * 0.40 weight = 0.20.
        #expect(abs(halfway.aggregateScore - 0.20) < 0.001)
    }

    @Test func pressureCapsAtOneForOverQuotaUsage() {
        let policy = UsageLimitPolicy.default
        let overUse = policy.computePressure(
            forProvider: "openai.codex",
            calls: 10_000,
            tokens: 10_000_000,
            cost: 1_000,
            sessionSeconds: 1_000_000
        )
        #expect(overUse.callsUsage == 1.0)
        #expect(overUse.tokensUsage == 1.0)
        #expect(overUse.costUsage == 1.0)
        #expect(overUse.sessionUsage == 1.0)
        #expect(overUse.aggregateScore == 1.0)
    }

    @Test func aggregateWeightingMatchesExpected() {
        let policy = UsageLimitPolicy.default
        let pressure = policy.computePressure(
            forProvider: "openai.codex",
            calls: 200, // 100% of calls quota
            tokens: 0,
            cost: 0,
            sessionSeconds: 0
        )
        // Calls weight 0.40, full saturation → 0.40
        #expect(abs(pressure.aggregateScore - 0.40) < 0.001)
    }

    @Test func dailyRefreshWindowReturnsNextMidnight() {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 14, minute: 38))!
        let next = RefreshWindow.daily.nextRefresh(after: reference, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: 0, minute: 0))!
        #expect(next == expected)
    }

    @Test func manualRefreshWindowReturnsNil() {
        let next = RefreshWindow.manual.nextRefresh(after: Date())
        #expect(next == nil)
    }

    // MARK: UsageSnapshotBuilder integration

    @Test func usageSnapshotIncludesLatencyAndSuccessRate() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let provider = AgentProviderProfile(draft: ProviderCatalog.defaultProfiles[0])
        provider.installedState = ProviderAvailabilityState.available.rawValue
        context.insert(provider)

        let usage = UsageLedgerEntry(
            providerID: provider.identifier,
            promptTokens: 1_000,
            completionTokens: 500,
            callCount: 4,
            estimatedCostUSD: 0.04,
            sessionSeconds: 240
        )
        context.insert(usage)

        // Three runs: 2 succeeded (12s + 18s), 1 failed.
        let success1 = RunOutcomeRecord(providerID: provider.identifier, status: RunStatus.succeeded.rawValue, durationSeconds: 12)
        let success2 = RunOutcomeRecord(providerID: provider.identifier, status: RunStatus.succeeded.rawValue, durationSeconds: 18)
        let failed1 = RunOutcomeRecord(providerID: provider.identifier, status: RunStatus.failed.rawValue, durationSeconds: 4)
        context.insert(success1)
        context.insert(success2)
        context.insert(failed1)
        try context.save()

        let snapshots = UsageSnapshotBuilder.build(
            from: try context.fetch(FetchDescriptor<UsageLedgerEntry>()),
            outcomes: try context.fetch(FetchDescriptor<RunOutcomeRecord>()),
            providers: try context.fetch(FetchDescriptor<AgentProviderProfile>())
        )

        let snapshot = try #require(snapshots.first)
        #expect(snapshot.callsToday == 4)
        #expect(snapshot.tokenCountToday == 1_500)
        #expect(snapshot.succeededRunsToday == 2)
        #expect(snapshot.failedRunsToday == 1)
        #expect(abs(snapshot.successRate - (2.0 / 3.0)) < 0.001)
        #expect(abs(snapshot.averageLatencySeconds - 15) < 0.001)
        #expect(snapshot.pressure?.callsUsage ?? 0 > 0)
    }

    // MARK: PerformanceHistoryBuilder

    @Test func performanceSummaryAggregatesAcrossRuns() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let provider = AgentProviderProfile(draft: ProviderCatalog.defaultProfiles[0])
        context.insert(provider)

        // Build 4 runs: 2 succeeded (rated correct + minorFix), 1 failed
        // (broke build), 1 cancelled. Plus matching usage entries for cost.
        let now = Date()
        let r1 = RunOutcomeRecord(
            runID: UUID().uuidString,
            providerID: provider.identifier,
            status: RunStatus.succeeded.rawValue,
            accuracyRating: AccuracyRating.correct.rawValue,
            startedAt: now.addingTimeInterval(-3600),
            durationSeconds: 20
        )
        let r2 = RunOutcomeRecord(
            runID: UUID().uuidString,
            providerID: provider.identifier,
            status: RunStatus.succeeded.rawValue,
            accuracyRating: AccuracyRating.minorFixNeeded.rawValue,
            startedAt: now.addingTimeInterval(-1800),
            durationSeconds: 10
        )
        let r3 = RunOutcomeRecord(
            runID: UUID().uuidString,
            providerID: provider.identifier,
            status: RunStatus.failed.rawValue,
            accuracyRating: AccuracyRating.brokeBuildOrTests.rawValue,
            startedAt: now.addingTimeInterval(-600),
            durationSeconds: 4
        )
        let r4 = RunOutcomeRecord(
            runID: UUID().uuidString,
            providerID: provider.identifier,
            status: RunStatus.cancelled.rawValue,
            accuracyRating: AccuracyRating.unrated.rawValue,
            startedAt: now,
            durationSeconds: 0
        )
        let usageEntries = [r1, r2, r3].map { run in
            UsageLedgerEntry(providerID: provider.identifier, runID: run.runID, estimatedCostUSD: 0.10)
        }

        context.insert(r1); context.insert(r2); context.insert(r3); context.insert(r4)
        for entry in usageEntries { context.insert(entry) }
        try context.save()

        let summaries = PerformanceHistoryBuilder.build(
            providers: try context.fetch(FetchDescriptor<AgentProviderProfile>()),
            outcomes: try context.fetch(FetchDescriptor<RunOutcomeRecord>()),
            usageEntries: try context.fetch(FetchDescriptor<UsageLedgerEntry>())
        )

        let summary = try #require(summaries.first { $0.providerID == provider.identifier })
        #expect(summary.totalRuns == 4)
        #expect(summary.succeededCount == 2)
        #expect(summary.failedCount == 1)
        #expect(summary.cancelledCount == 1)
        #expect(summary.ratedRunCount == 3) // r1/r2/r3 rated, r4 unrated
        // Success rate = succeeded / (succeeded + failed) = 2 / 3
        #expect(abs(summary.successRate - (2.0 / 3.0)) < 0.001)
        // Avg duration over succeeded runs only = (20 + 10) / 2 = 15
        #expect(abs(summary.averageDurationSeconds - 15) < 0.001)
        // Trendline ordered chronologically (earliest first)
        #expect(summary.trendline.count == 4)
        #expect(summary.trendline.first?.runIndex == 1)
        #expect(summary.trendline.last?.runIndex == 4)
        #expect(summary.trendline.last?.cancelled == true)
    }

    @Test func performanceSummarySkipsProvidersWithoutRuns() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let provider = AgentProviderProfile(draft: ProviderCatalog.defaultProfiles[1])
        context.insert(provider)
        try context.save()

        let summaries = PerformanceHistoryBuilder.build(
            providers: try context.fetch(FetchDescriptor<AgentProviderProfile>()),
            outcomes: []
        )

        let summary = try #require(summaries.first)
        #expect(summary.totalRuns == 0)
        #expect(summary.successRate == 1.0) // empty denominator → optimistic 1.0
        #expect(summary.trendline.isEmpty)
    }

    @Test func dashboardHeatmapIncludesLatencyAndSuccessMetrics() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let provider = AgentProviderProfile(draft: ProviderCatalog.defaultProfiles[0])
        provider.installedState = ProviderAvailabilityState.available.rawValue
        context.insert(provider)
        try context.save()

        let providers = try context.fetch(FetchDescriptor<AgentProviderProfile>())
        let usage = UsageSnapshotBuilder.build(
            from: [],
            outcomes: [],
            providers: providers
        )
        let accuracy = AccuracySnapshotBuilder.build(from: [], providers: providers)
        let cells = DashboardMetricFactory.heatmapCells(
            providers: providers,
            usage: usage,
            accuracy: accuracy
        )

        let metricNames = Set(cells.map(\.metricName))
        #expect(metricNames.contains("Latency"))
        #expect(metricNames.contains("Success"))
        #expect(metricNames.contains("Availability"))
        #expect(metricNames.contains("Cost"))
        // Six metrics × one provider = six cells.
        #expect(cells.count == 6)
    }
}
