//
//  AutonomyLoopReportRetentionTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint Q.10: bound the persisted loop report store.
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@Suite("Sprint Q.10 loop report retention")
struct AutonomyLoopReportRetentionTests {
    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    private static func record(
        identifier: String,
        planID: String,
        endedAt: Date
    ) -> AutonomousLoopReportRecord {
        AutonomousLoopReportRecord(
            identifier: identifier,
            goalID: "goal-\(planID)",
            planID: planID,
            haltReasonKind: "completed",
            haltReasonLabel: "Plan walked to completion.",
            startedAt: endedAt.addingTimeInterval(-30),
            endedAt: endedAt
        )
    }

    private static let referenceNow = Date(timeIntervalSince1970: 2_000_000)
    private static let day: TimeInterval = 86_400

    // MARK: Pure prune algorithm

    @Test func defaultPolicyKeepsAllReportsWithinSmallStore() {
        let reports = (0..<5).map { index in
            Self.record(
                identifier: "r-\(index)",
                planID: "plan-a",
                endedAt: Self.referenceNow.addingTimeInterval(-Double(index) * Self.day)
            )
        }
        let ids = AutonomyLoopReportRetentionPolicy.prune(
            reports: reports,
            policy: .default,
            now: Self.referenceNow
        )
        #expect(ids.isEmpty)
    }

    @Test func perPlanCapPrunesOldestReports() {
        let policy = AutonomyLoopReportRetentionPolicy(maxReportsPerPlan: 3, maxAgeDays: nil)
        let reports = (0..<6).map { index in
            Self.record(
                identifier: "r-\(index)",
                planID: "plan-a",
                endedAt: Self.referenceNow.addingTimeInterval(-Double(index) * Self.day)
            )
        }
        let ids = Set(AutonomyLoopReportRetentionPolicy.prune(
            reports: reports,
            policy: policy,
            now: Self.referenceNow
        ))
        #expect(ids == ["r-3", "r-4", "r-5"])
    }

    @Test func mostRecentReportPerPlanIsAlwaysPreserved() {
        // Even though the only report is older than the age limit,
        // retention keeps the latest-per-plan to avoid blank history.
        let policy = AutonomyLoopReportRetentionPolicy(maxReportsPerPlan: 5, maxAgeDays: 1)
        let ancient = Self.record(
            identifier: "r-ancient",
            planID: "plan-a",
            endedAt: Self.referenceNow.addingTimeInterval(-100 * Self.day)
        )
        let ids = AutonomyLoopReportRetentionPolicy.prune(
            reports: [ancient],
            policy: policy,
            now: Self.referenceNow
        )
        #expect(ids.isEmpty)
    }

    @Test func ageLimitDropsOldReportsButKeepsLatestPerPlan() {
        let policy = AutonomyLoopReportRetentionPolicy(maxReportsPerPlan: 100, maxAgeDays: 7)
        let reports = [
            Self.record(identifier: "r-fresh", planID: "plan-a", endedAt: Self.referenceNow),
            Self.record(identifier: "r-recent", planID: "plan-a", endedAt: Self.referenceNow.addingTimeInterval(-2 * Self.day)),
            Self.record(identifier: "r-stale", planID: "plan-a", endedAt: Self.referenceNow.addingTimeInterval(-30 * Self.day)),
            Self.record(identifier: "r-ancient", planID: "plan-a", endedAt: Self.referenceNow.addingTimeInterval(-365 * Self.day)),
        ]
        let ids = Set(AutonomyLoopReportRetentionPolicy.prune(
            reports: reports,
            policy: policy,
            now: Self.referenceNow
        ))
        #expect(ids == ["r-stale", "r-ancient"])
    }

    @Test func retentionScopesEachPlanSeparately() {
        let policy = AutonomyLoopReportRetentionPolicy(maxReportsPerPlan: 1, maxAgeDays: nil)
        // Each plan has 3 reports — retention should keep the latest
        // for each, dropping 2 per plan.
        var reports: [AutonomousLoopReportRecord] = []
        for plan in ["plan-a", "plan-b"] {
            for index in 0..<3 {
                reports.append(Self.record(
                    identifier: "\(plan)-r\(index)",
                    planID: plan,
                    endedAt: Self.referenceNow.addingTimeInterval(-Double(index) * Self.day)
                ))
            }
        }
        let ids = Set(AutonomyLoopReportRetentionPolicy.prune(
            reports: reports,
            policy: policy,
            now: Self.referenceNow
        ))
        #expect(ids == ["plan-a-r1", "plan-a-r2", "plan-b-r1", "plan-b-r2"])
    }

    // MARK: Clamping

    @Test func clampedAcceptsInRangeValues() {
        let policy = AutonomyLoopReportRetentionPolicy.clamped(
            maxReportsPerPlan: 10,
            maxAgeDaysOrZero: 30
        )
        #expect(policy.maxReportsPerPlan == 10)
        #expect(policy.maxAgeDays == 30)
    }

    @Test func clampedTreatsZeroAgeAsDisabled() {
        let policy = AutonomyLoopReportRetentionPolicy.clamped(
            maxReportsPerPlan: 5,
            maxAgeDaysOrZero: 0
        )
        #expect(policy.maxAgeDays == nil)
    }

    @Test func clampedRaisesBelowMinValues() {
        let policy = AutonomyLoopReportRetentionPolicy.clamped(
            maxReportsPerPlan: -5,
            maxAgeDaysOrZero: -10
        )
        #expect(policy.maxReportsPerPlan == AutonomyLoopReportRetentionPolicy.minMaxReportsPerPlan)
        #expect(policy.maxAgeDays == nil)
    }

    @Test func clampedLowersAboveMaxValues() {
        let policy = AutonomyLoopReportRetentionPolicy.clamped(
            maxReportsPerPlan: 10_000,
            maxAgeDaysOrZero: 10_000
        )
        #expect(policy.maxReportsPerPlan == AutonomyLoopReportRetentionPolicy.maxMaxReportsPerPlan)
        #expect(policy.maxAgeDays == AutonomyLoopReportRetentionPolicy.maxMaxAgeDaysStorageValue)
    }

    @Test func summaryIncludesCapAndAge() {
        let withAge = AutonomyLoopReportRetentionPolicy(maxReportsPerPlan: 12, maxAgeDays: 30).summary
        #expect(withAge.contains("12"))
        #expect(withAge.contains("30"))
        let noAge = AutonomyLoopReportRetentionPolicy(maxReportsPerPlan: 8, maxAgeDays: nil).summary
        #expect(noAge.contains("8"))
        #expect(noAge.contains("no age limit"))
    }

    // MARK: Persistence integration

    @MainActor
    @Test func applyRetentionDeletesPrunedRecordsFromSwiftData() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        // 5 reports for the same plan, oldest first by endedAt
        for index in 0..<5 {
            context.insert(Self.record(
                identifier: "r-\(index)",
                planID: "plan-a",
                endedAt: Self.referenceNow.addingTimeInterval(-Double(index) * Self.day)
            ))
        }
        try context.save()

        let policy = AutonomyLoopReportRetentionPolicy(maxReportsPerPlan: 2, maxAgeDays: nil)
        let deleted = AutonomousLoopPersistence.applyRetention(
            policy: policy,
            modelContext: context,
            now: Self.referenceNow
        )
        #expect(deleted == 3)

        let remaining = try context.fetch(FetchDescriptor<AutonomousLoopReportRecord>())
        let remainingIDs = Set(remaining.map(\.identifier))
        #expect(remainingIDs == ["r-0", "r-1"])
    }

    @MainActor
    @Test func applyRetentionReturnsZeroWhenNoPruningNeeded() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        context.insert(Self.record(
            identifier: "r-single",
            planID: "plan-a",
            endedAt: Self.referenceNow
        ))
        try context.save()

        let deleted = AutonomousLoopPersistence.applyRetention(
            policy: .default,
            modelContext: context,
            now: Self.referenceNow
        )
        #expect(deleted == 0)
        let remaining = try context.fetch(FetchDescriptor<AutonomousLoopReportRecord>())
        #expect(remaining.count == 1)
    }
}
