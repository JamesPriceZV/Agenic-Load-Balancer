//
//  AutonomyLoopReportStatisticsTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint Q.11: aggregate metrics over the persisted loop reports.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Sprint Q.11 loop report statistics")
struct AutonomyLoopReportStatisticsTests {
    private static let referenceNow = Date(timeIntervalSince1970: 2_000_000)
    private static let day: TimeInterval = 86_400

    private static func iteration(
        index: Int,
        status: AutonomousLoopIteration.Status
    ) -> AutonomousLoopIteration {
        AutonomousLoopIteration(
            index: index,
            taskID: "task-\(index)",
            taskTitle: "Task \(index)",
            mode: AgentExecutionMode.implementation.rawValue,
            status: status,
            detail: "iter \(index)",
            occurredAt: Self.referenceNow
        )
    }

    private static func encodeIterations(_ iterations: [AutonomousLoopIteration]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(iterations),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private static func record(
        identifier: String,
        planID: String = "plan-a",
        haltReasonKind: String = "completed",
        validationFailureCount: Int = 0,
        endedAt: Date,
        iterationCount: Int = 4
    ) -> AutonomousLoopReportRecord {
        let iterations = (0..<iterationCount).map {
            iteration(index: $0, status: .validationPassed)
        }
        return AutonomousLoopReportRecord(
            identifier: identifier,
            goalID: "goal-\(planID)",
            planID: planID,
            haltReasonKind: haltReasonKind,
            haltReasonLabel: "label",
            iterationsJSON: encodeIterations(iterations),
            validationFailureCount: validationFailureCount,
            startedAt: endedAt.addingTimeInterval(-30),
            endedAt: endedAt
        )
    }

    @Test func emptyStoreReturnsZeroStats() {
        let stats = AutonomyLoopReportStatistics.compute(from: [], now: Self.referenceNow)
        #expect(stats.totalReports == 0)
        #expect(stats.completedCount == 0)
        #expect(stats.averageIterationsPerReport == nil)
        #expect(stats.successRate == nil)
        #expect(stats.mostCommonHaltReasonKind == nil)
        #expect(stats.successRateLabel == "—")
        #expect(stats.averageIterationsLabel == "—")
    }

    @Test func countsTotalAndRecentReports() {
        let reports = [
            Self.record(identifier: "r0", endedAt: Self.referenceNow),
            Self.record(identifier: "r1", endedAt: Self.referenceNow.addingTimeInterval(-1 * Self.day)),
            Self.record(identifier: "r2", endedAt: Self.referenceNow.addingTimeInterval(-6 * Self.day)),
            Self.record(identifier: "r3", endedAt: Self.referenceNow.addingTimeInterval(-30 * Self.day)),
        ]
        let stats = AutonomyLoopReportStatistics.compute(from: reports, now: Self.referenceNow)
        #expect(stats.totalReports == 4)
        // 3 reports within the last 7 days (r0, r1, r2).
        #expect(stats.reportsInLastSevenDays == 3)
    }

    @Test func successRateIsCompletedOverTotal() {
        let reports = [
            Self.record(identifier: "r0", haltReasonKind: "completed", endedAt: Self.referenceNow),
            Self.record(identifier: "r1", haltReasonKind: "completed", endedAt: Self.referenceNow),
            Self.record(identifier: "r2", haltReasonKind: "validationFailureCap", endedAt: Self.referenceNow),
            Self.record(identifier: "r3", haltReasonKind: "approvalRequired", endedAt: Self.referenceNow),
        ]
        let stats = AutonomyLoopReportStatistics.compute(from: reports, now: Self.referenceNow)
        #expect(stats.completedCount == 2)
        #expect(stats.successRate == 0.5)
        #expect(stats.successRateLabel == "50%")
    }

    @Test func validationFailuresAreSummedAcrossReports() {
        let reports = [
            Self.record(identifier: "r0", validationFailureCount: 0, endedAt: Self.referenceNow),
            Self.record(identifier: "r1", validationFailureCount: 2, endedAt: Self.referenceNow),
            Self.record(identifier: "r2", validationFailureCount: 1, endedAt: Self.referenceNow),
        ]
        let stats = AutonomyLoopReportStatistics.compute(from: reports, now: Self.referenceNow)
        #expect(stats.validationFailureCount == 3)
    }

    @Test func averageIterationsRoundsToOneDecimal() {
        let reports = [
            Self.record(identifier: "r0", endedAt: Self.referenceNow, iterationCount: 1),
            Self.record(identifier: "r1", endedAt: Self.referenceNow, iterationCount: 4),
            Self.record(identifier: "r2", endedAt: Self.referenceNow, iterationCount: 5),
        ]
        let stats = AutonomyLoopReportStatistics.compute(from: reports, now: Self.referenceNow)
        #expect(stats.totalIterations == 10)
        #expect(stats.averageIterationsPerReport == 10.0 / 3.0)
        #expect(stats.averageIterationsLabel == "3.3")
    }

    @Test func mostCommonHaltReasonReflectsMajority() {
        let reports = [
            Self.record(identifier: "r0", haltReasonKind: "completed", endedAt: Self.referenceNow),
            Self.record(identifier: "r1", haltReasonKind: "completed", endedAt: Self.referenceNow),
            Self.record(identifier: "r2", haltReasonKind: "completed", endedAt: Self.referenceNow),
            Self.record(identifier: "r3", haltReasonKind: "validationFailureCap", endedAt: Self.referenceNow),
        ]
        let stats = AutonomyLoopReportStatistics.compute(from: reports, now: Self.referenceNow)
        #expect(stats.mostCommonHaltReasonKind == "completed")
        #expect(stats.mostCommonHaltReasonCount == 3)
    }

    @Test func mostCommonHaltReasonTieBreaksOnAscendingKey() {
        // Two halt reasons tied at 2 each. Stable output must pick
        // the lexicographically smaller key.
        let reports = [
            Self.record(identifier: "r0", haltReasonKind: "completed", endedAt: Self.referenceNow),
            Self.record(identifier: "r1", haltReasonKind: "completed", endedAt: Self.referenceNow),
            Self.record(identifier: "r2", haltReasonKind: "denied", endedAt: Self.referenceNow),
            Self.record(identifier: "r3", haltReasonKind: "denied", endedAt: Self.referenceNow),
        ]
        let stats = AutonomyLoopReportStatistics.compute(from: reports, now: Self.referenceNow)
        #expect(stats.mostCommonHaltReasonKind == "completed")
    }

    @Test func successRateLabelRoundsToNearestPercent() {
        let twoOfThree = [
            Self.record(identifier: "r0", haltReasonKind: "completed", endedAt: Self.referenceNow),
            Self.record(identifier: "r1", haltReasonKind: "completed", endedAt: Self.referenceNow),
            Self.record(identifier: "r2", haltReasonKind: "denied", endedAt: Self.referenceNow),
        ]
        let stats = AutonomyLoopReportStatistics.compute(from: twoOfThree, now: Self.referenceNow)
        // 0.6666... rounds to 67%.
        #expect(stats.successRateLabel == "67%")
    }
}
