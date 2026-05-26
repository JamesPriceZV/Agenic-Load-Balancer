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

struct ProviderReliabilitySnapshot: Sendable, Hashable, Identifiable {
    let providerID: String
    let providerName: String
    let recentRunCount: Int
    let succeededRunCount: Int
    let failedRunCount: Int
    let cancelledRunCount: Int
    let quotaLimitedRunCount: Int
    let rateLimitedRunCount: Int
    let contextLimitedRunCount: Int
    let reliabilityScore: Double
    let summary: String
    /// Sprint P.1: continuation chain telemetry surfaced for the dashboard
    /// and routing. Default zero so callers that build a snapshot from
    /// older paths keep compiling; the standard builder populates these
    /// from `RunOutcomeRecord.continuation*` fields.
    let continuationOfferedRunCount: Int
    let continuationAutoResumeRunCount: Int
    let continuationApprovalGatedRunCount: Int
    let continuationRefusedRunCount: Int
    let maxContinuationChainDepth: Int

    var id: String { providerID }

    init(
        providerID: String,
        providerName: String,
        recentRunCount: Int,
        succeededRunCount: Int,
        failedRunCount: Int,
        cancelledRunCount: Int,
        quotaLimitedRunCount: Int,
        rateLimitedRunCount: Int,
        contextLimitedRunCount: Int,
        reliabilityScore: Double,
        summary: String,
        continuationOfferedRunCount: Int = 0,
        continuationAutoResumeRunCount: Int = 0,
        continuationApprovalGatedRunCount: Int = 0,
        continuationRefusedRunCount: Int = 0,
        maxContinuationChainDepth: Int = 0
    ) {
        self.providerID = providerID
        self.providerName = providerName
        self.recentRunCount = recentRunCount
        self.succeededRunCount = succeededRunCount
        self.failedRunCount = failedRunCount
        self.cancelledRunCount = cancelledRunCount
        self.quotaLimitedRunCount = quotaLimitedRunCount
        self.rateLimitedRunCount = rateLimitedRunCount
        self.contextLimitedRunCount = contextLimitedRunCount
        self.reliabilityScore = reliabilityScore
        self.summary = summary
        self.continuationOfferedRunCount = continuationOfferedRunCount
        self.continuationAutoResumeRunCount = continuationAutoResumeRunCount
        self.continuationApprovalGatedRunCount = continuationApprovalGatedRunCount
        self.continuationRefusedRunCount = continuationRefusedRunCount
        self.maxContinuationChainDepth = maxContinuationChainDepth
    }
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

enum ProviderReliabilityBuilder {
    static func build(
        providers: [AgentProviderProfile],
        outcomes: [RunOutcomeRecord],
        recentLimit: Int = 12
    ) -> [ProviderReliabilitySnapshot] {
        let outcomesByProvider = Dictionary(grouping: outcomes, by: { $0.providerID })

        return providers.map { provider in
            let recent = Array(
                (outcomesByProvider[provider.identifier] ?? [])
                    .filter { outcome in
                        switch RunStatus(rawValue: outcome.status) {
                        case .succeeded, .failed, .cancelled:
                            return true
                        case .proposed, .approved, .running, .none:
                            return false
                        }
                    }
                    .sorted { $0.startedAt < $1.startedAt }
                    .suffix(recentLimit)
            )

            let succeeded = recent.filter { $0.status == RunStatus.succeeded.rawValue }
            let failed = recent.filter { $0.status == RunStatus.failed.rawValue }
            let cancelled = recent.filter { $0.status == RunStatus.cancelled.rawValue }
            let limitStatuses = recent.map { ProviderProbeClassifier.limitStatus(fromOutput: failureText(for: $0)) }
            let quotaLimited = limitStatuses.filter { $0 == .quotaLimited || $0 == .subscriptionLimited }.count
            let rateLimited = limitStatuses.filter { $0 == .rateLimited }.count
            let contextLimited = limitStatuses.filter { $0 == .contextLimited }.count

            // Sprint P.1: continuation telemetry. A continuation is
            // "offered" when an outcome was tagged with a trigger
            // category (chain machinery actually fired). The policy-note
            // text distinguishes refusals (over cap / ineligible
            // trigger) from prepared resumes; the requires-approval flag
            // distinguishes approval-gated from auto-resume.
            let continuationOutcomes = recent.filter {
                ($0.continuationTriggerCategory?.isEmpty == false) ||
                ($0.continuationPolicyNote?.isEmpty == false) ||
                ($0.continuationChainDepth) > 0
            }
            let continuationRefused = continuationOutcomes.filter { outcome in
                guard let note = outcome.continuationPolicyNote?.lowercased() else { return false }
                return note.contains("exceed policy cap") ||
                    note.contains("provider policy excludes") ||
                    note.contains("policy excludes trigger") ||
                    note.contains("would exceed")
            }
            let continuationPrepared = continuationOutcomes.filter {
                ($0.continuationPrompt?.isEmpty == false)
            }
            let continuationAutoResume = continuationPrepared.filter { !$0.continuationRequiresApproval }
            let continuationApprovalGated = continuationPrepared.filter { $0.continuationRequiresApproval }
            let maxChainDepth = recent.map(\.continuationChainDepth).max() ?? 0

            let total = recent.count
            let reliabilityScore: Double
            if total == 0 {
                reliabilityScore = 0.70
            } else {
                let successRate = Double(succeeded.count) / Double(total)
                let failureRate = Double(failed.count) / Double(total)
                let cancelRate = Double(cancelled.count) / Double(total)
                let limitPenalty = Double(quotaLimited + rateLimited + contextLimited) / Double(max(total, 1))
                // Sprint P.1: refusal penalty is small but non-zero — the
                // policy ran out of room to keep retrying, which is a
                // genuine reliability signal beyond raw failure rate.
                let continuationRefusalPenalty = Double(continuationRefused.count) / Double(max(total, 1))
                reliabilityScore = max(
                    0,
                    min(
                        1,
                        0.48
                            + successRate * 0.42
                            - failureRate * 0.20
                            - cancelRate * 0.08
                            - limitPenalty * 0.14
                            - continuationRefusalPenalty * 0.06
                    )
                )
            }

            let summary: String
            if total == 0 {
                summary = "No recent run history; using neutral reliability."
            } else {
                var parts: [String] = [
                    "\(succeeded.count)/\(total) recent run(s) succeeded; \(failed.count) failed; \(cancelled.count) cancelled."
                ]
                if continuationOutcomes.isEmpty == false {
                    parts.append(
                        "Continuation chains: \(continuationAutoResume.count) auto-resume / \(continuationApprovalGated.count) approval-gated / \(continuationRefused.count) refused; deepest chain depth observed = \(maxChainDepth)."
                    )
                }
                summary = parts.joined(separator: " ")
            }

            return ProviderReliabilitySnapshot(
                providerID: provider.identifier,
                providerName: provider.displayName,
                recentRunCount: total,
                succeededRunCount: succeeded.count,
                failedRunCount: failed.count,
                cancelledRunCount: cancelled.count,
                quotaLimitedRunCount: quotaLimited,
                rateLimitedRunCount: rateLimited,
                contextLimitedRunCount: contextLimited,
                reliabilityScore: reliabilityScore,
                summary: summary,
                continuationOfferedRunCount: continuationOutcomes.count,
                continuationAutoResumeRunCount: continuationAutoResume.count,
                continuationApprovalGatedRunCount: continuationApprovalGated.count,
                continuationRefusedRunCount: continuationRefused.count,
                maxContinuationChainDepth: maxChainDepth
            )
        }
    }

    private static func failureText(for outcome: RunOutcomeRecord) -> String {
        [
            outcome.buildResult,
            outcome.userFeedback,
            outcome.aiOneLineDescription,
            outcome.continuationSummary,
            outcome.contextBudgetSummary,
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}
