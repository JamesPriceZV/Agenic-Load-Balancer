//
//  PerformanceHistory.swift
//  Agenic Load-Balancer
//
//  Created by Claude on 5/5/26.
//
//  Phase 4: derive per-provider model-performance trendlines from the
//  RunOutcome and UsageLedger SwiftData records. The dashboard renders
//  these via Swift Charts; the routing engine could later weight scoring
//  decisions by recent trend deltas as well.
//

import Foundation

/// One run's worth of performance signal for a provider.
struct ProviderPerformancePoint: Sendable, Hashable, Identifiable {
    let id: String
    let providerID: String
    let providerName: String
    let timestamp: Date
    let runIndex: Int
    let accuracyScore: Double
    let durationSeconds: Double
    let estimatedCostUSD: Double
    let succeeded: Bool
    let cancelled: Bool
    let accuracyRating: AccuracyRating
}

/// Aggregated performance figures for a provider, plus a recent trendline.
struct ProviderPerformanceSummary: Sendable, Hashable, Identifiable {
    let providerID: String
    let providerName: String
    let totalRuns: Int
    let succeededCount: Int
    let failedCount: Int
    let cancelledCount: Int
    let ratedRunCount: Int
    let averageAccuracy: Double
    let averageDurationSeconds: Double
    let averageCostUSD: Double
    let successRate: Double
    let lastRunAt: Date?
    let trendline: [ProviderPerformancePoint]

    var id: String { providerID }
}

enum PerformanceHistoryBuilder {
    /// Build per-provider performance summaries.
    ///
    /// `recentLimit` controls how many of the most recent outcomes (per
    /// provider) feed the trendline. The summary aggregates over the full
    /// outcome list so totals remain accurate even when the trendline is
    /// truncated.
    static func build(
        providers: [AgentProviderProfile],
        outcomes: [RunOutcomeRecord],
        usageEntries: [UsageLedgerEntry] = [],
        recentLimit: Int = 30
    ) -> [ProviderPerformanceSummary] {
        let outcomesByProvider = Dictionary(
            grouping: outcomes,
            by: { $0.providerID }
        )
        let usageByRun: [String: UsageLedgerEntry] = Dictionary(
            usageEntries.compactMap { entry -> (String, UsageLedgerEntry)? in
                guard let runID = entry.runID else { return nil }
                return (runID, entry)
            },
            uniquingKeysWith: { _, b in b }
        )

        return providers.map { provider in
            let providerOutcomes = (outcomesByProvider[provider.identifier] ?? [])
                .sorted { $0.startedAt < $1.startedAt }

            let succeededOutcomes = providerOutcomes.filter {
                $0.status == RunStatus.succeeded.rawValue
            }
            let failedOutcomes = providerOutcomes.filter {
                $0.status == RunStatus.failed.rawValue
            }
            let cancelledOutcomes = providerOutcomes.filter {
                $0.status == RunStatus.cancelled.rawValue
            }
            let ratedOutcomes = providerOutcomes.filter {
                AccuracyRating(rawValue: $0.accuracyRating).map { $0 != .unrated } ?? false
            }

            let durations = succeededOutcomes.map(\.durationSeconds).filter { $0 > 0 }
            let avgDuration = durations.isEmpty
                ? 0
                : durations.reduce(0, +) / Double(durations.count)

            let costs = providerOutcomes.compactMap { usageByRun[$0.runID]?.estimatedCostUSD }
            let avgCost = costs.isEmpty ? 0 : costs.reduce(0, +) / Double(costs.count)

            let outcomeDenominator = succeededOutcomes.count + failedOutcomes.count
            let successRate = outcomeDenominator == 0
                ? 1.0
                : Double(succeededOutcomes.count) / Double(outcomeDenominator)

            let accuracyContributions = providerOutcomes
                .compactMap { AccuracyRating(rawValue: $0.accuracyRating)?.scoreContribution }
            let averageAccuracy: Double
            if accuracyContributions.isEmpty {
                averageAccuracy = AccuracyRating.unrated.scoreContribution
            } else {
                averageAccuracy = accuracyContributions.reduce(0, +) / Double(accuracyContributions.count)
            }

            let trimmed = Array(providerOutcomes.suffix(recentLimit))
            let trendline: [ProviderPerformancePoint] = trimmed
                .enumerated()
                .map { (index, outcome) in
                    let rating = AccuracyRating(rawValue: outcome.accuracyRating) ?? .unrated
                    return ProviderPerformancePoint(
                        id: outcome.identifier,
                        providerID: provider.identifier,
                        providerName: provider.displayName,
                        timestamp: outcome.startedAt,
                        runIndex: index + 1,
                        accuracyScore: rating.scoreContribution,
                        durationSeconds: outcome.durationSeconds,
                        estimatedCostUSD: usageByRun[outcome.runID]?.estimatedCostUSD ?? 0,
                        succeeded: outcome.status == RunStatus.succeeded.rawValue,
                        cancelled: outcome.status == RunStatus.cancelled.rawValue,
                        accuracyRating: rating
                    )
                }

            return ProviderPerformanceSummary(
                providerID: provider.identifier,
                providerName: provider.displayName,
                totalRuns: providerOutcomes.count,
                succeededCount: succeededOutcomes.count,
                failedCount: failedOutcomes.count,
                cancelledCount: cancelledOutcomes.count,
                ratedRunCount: ratedOutcomes.count,
                averageAccuracy: averageAccuracy,
                averageDurationSeconds: avgDuration,
                averageCostUSD: avgCost,
                successRate: successRate,
                lastRunAt: providerOutcomes.last?.startedAt,
                trendline: trendline
            )
        }
    }
}
