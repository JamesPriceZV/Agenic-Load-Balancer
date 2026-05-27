//
//  AutonomyLoopReportStatistics.swift
//  Agenic Load-Balancer
//
//  Sprint Q.11: aggregate metrics over the persisted loop report
//  store so the Autonomy control room can show how the scheduler is
//  doing without forcing the user to drill into every record. Pure
//  aggregation — no SwiftData mutation, no global state, no clock
//  except the caller-supplied `now`.
//

import Foundation

struct AutonomyLoopReportStatistics: Sendable, Hashable {
    let totalReports: Int
    let reportsInLastSevenDays: Int
    let completedCount: Int
    let validationFailureCount: Int
    let totalIterations: Int
    /// `nil` when there are no reports yet.
    let averageIterationsPerReport: Double?
    /// `nil` when there are no reports yet.
    let successRate: Double?
    /// `nil` when there are no reports yet.
    let mostCommonHaltReasonKind: String?
    let mostCommonHaltReasonCount: Int

    static let empty = AutonomyLoopReportStatistics(
        totalReports: 0,
        reportsInLastSevenDays: 0,
        completedCount: 0,
        validationFailureCount: 0,
        totalIterations: 0,
        averageIterationsPerReport: nil,
        successRate: nil,
        mostCommonHaltReasonKind: nil,
        mostCommonHaltReasonCount: 0
    )

    static func compute(
        from reports: [AutonomousLoopReportRecord],
        now: Date = Date()
    ) -> AutonomyLoopReportStatistics {
        guard !reports.isEmpty else { return .empty }

        let total = reports.count
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86_400)
        let recent = reports.filter { $0.endedAt >= sevenDaysAgo }.count
        let completed = reports.filter { $0.haltReasonKind == "completed" }.count
        let validationFailures = reports
            .map(\.validationFailureCount)
            .reduce(0, +)
        let totalIterations = reports
            .map { AutonomousLoopPersistence.decodeIterations($0.iterationsJSON).count }
            .reduce(0, +)

        let counts = Dictionary(grouping: reports, by: \.haltReasonKind)
            .mapValues(\.count)
        // Sort by count desc, then key asc for stable output when
        // multiple kinds tie.
        let topKind = counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .first

        return AutonomyLoopReportStatistics(
            totalReports: total,
            reportsInLastSevenDays: recent,
            completedCount: completed,
            validationFailureCount: validationFailures,
            totalIterations: totalIterations,
            averageIterationsPerReport: Double(totalIterations) / Double(total),
            successRate: Double(completed) / Double(total),
            mostCommonHaltReasonKind: topKind?.key,
            mostCommonHaltReasonCount: topKind?.value ?? 0
        )
    }

    /// Human-readable success rate as a percentage with no decimals
    /// (`"86%"`). Returns `"—"` when no reports exist yet.
    var successRateLabel: String {
        guard let rate = successRate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }

    /// Human-readable average iterations rounded to one decimal
    /// (`"4.2"`). Returns `"—"` when no reports exist yet.
    var averageIterationsLabel: String {
        guard let avg = averageIterationsPerReport else { return "—" }
        return String(format: "%.1f", avg)
    }
}
