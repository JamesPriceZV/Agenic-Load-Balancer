//
//  RoutingEngine.swift
//  Agenic Load-Balancer
//
//  Created by OpenAI Codex on 5/5/26.
//

import Foundation

struct RoutingScoreBreakdown: Identifiable, Sendable, Hashable {
    let id: UUID
    let providerID: String
    let providerName: String
    let mode: AgentExecutionMode
    let totalScore: Double
    let availabilityScore: Double
    let capabilityScore: Double
    let limitScore: Double
    let accuracyScore: Double
    let speedScore: Double
    let costScore: Double
    let rationale: String
    let estimatedCostUSD: Double
    let limitImpact: String
    let coordinationWarning: String

    init(
        id: UUID = UUID(),
        providerID: String,
        providerName: String,
        mode: AgentExecutionMode,
        totalScore: Double,
        availabilityScore: Double,
        capabilityScore: Double,
        limitScore: Double,
        accuracyScore: Double,
        speedScore: Double,
        costScore: Double,
        rationale: String,
        estimatedCostUSD: Double,
        limitImpact: String,
        coordinationWarning: String
    ) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.mode = mode
        self.totalScore = totalScore
        self.availabilityScore = availabilityScore
        self.capabilityScore = capabilityScore
        self.limitScore = limitScore
        self.accuracyScore = accuracyScore
        self.speedScore = speedScore
        self.costScore = costScore
        self.rationale = rationale
        self.estimatedCostUSD = estimatedCostUSD
        self.limitImpact = limitImpact
        self.coordinationWarning = coordinationWarning
    }
}

actor RoutingEngine {
    nonisolated static func closeScoreCandidates(
        from ranked: [RoutingScoreBreakdown],
        threshold: Double = 0.035,
        limit: Int = 3
    ) -> [RoutingScoreBreakdown] {
        guard let top = ranked.first else { return [] }
        return Array(
            ranked
                .prefix(max(1, limit))
                .filter { abs(top.totalScore - $0.totalScore) <= threshold }
        )
    }

    func rank(
        prompt: String,
        mode: AgentExecutionMode,
        providers: [AgentProviderSnapshot],
        usage: [UsageSnapshot],
        accuracy: [AccuracySnapshot],
        coordinationEvents: [CoordinationEventSnapshot]
    ) -> [RoutingScoreBreakdown] {
        let promptSignals = PromptSignalAnalyzer.analyze(prompt)
        let usageByProvider = Dictionary(uniqueKeysWithValues: usage.map { ($0.providerID, $0) })
        let accuracyByProvider = Dictionary(uniqueKeysWithValues: accuracy.map { ($0.providerID, $0) })
        let activeConflicts = coordinationEvents.filter { event in
            event.status == CoordinationStatus.inProgress.rawValue ||
            event.status == CoordinationStatus.claimed.rawValue ||
            event.status == CoordinationStatus.conflict.rawValue
        }

        return providers
            .filter(\.isEnabled)
            .map { provider in
                let providerUsage = usageByProvider[provider.identifier]
                let providerAccuracy = accuracyByProvider[provider.identifier]
                let availabilityScore = scoreAvailability(provider)
                let capabilityScore = scoreCapability(provider, mode: mode, promptSignals: promptSignals)
                let limitScore = max(0, 1 - (providerUsage?.limitPressure ?? 0.18))
                let accuracyScore = providerAccuracy?.averageScore ?? 0.62
                let speedScore = scoreSpeed(providerID: provider.identifier, usage: providerUsage)
                let estimatedCost = estimateCost(prompt: prompt, usage: providerUsage, provider: provider)
                let costScore = scoreCost(estimatedCost)
                let coordinationWarning = coordinationWarning(for: mode, activeConflicts: activeConflicts)

                let weightedScore =
                    availabilityScore * 0.24 +
                    capabilityScore * 0.20 +
                    limitScore * 0.18 +
                    accuracyScore * 0.20 +
                    speedScore * 0.08 +
                    costScore * 0.06 +
                    (coordinationWarning.isEmpty ? 0.04 : 0)

                return RoutingScoreBreakdown(
                    providerID: provider.identifier,
                    providerName: provider.displayName,
                    mode: mode,
                    totalScore: weightedScore,
                    availabilityScore: availabilityScore,
                    capabilityScore: capabilityScore,
                    limitScore: limitScore,
                    accuracyScore: accuracyScore,
                    speedScore: speedScore,
                    costScore: costScore,
                    rationale: rationale(
                        provider: provider,
                        mode: mode,
                        availabilityScore: availabilityScore,
                        capabilityScore: capabilityScore,
                        limitScore: limitScore,
                        accuracyScore: accuracyScore,
                        coordinationWarning: coordinationWarning
                    ),
                    estimatedCostUSD: estimatedCost,
                    limitImpact: limitImpact(providerUsage),
                    coordinationWarning: coordinationWarning
                )
            }
            .sorted { $0.totalScore > $1.totalScore }
    }

    private func scoreAvailability(_ provider: AgentProviderSnapshot) -> Double {
        switch provider.installedState {
        case .available:
            provider.authState == .authenticated || provider.authState == .custom ? 1.0 : 0.78
        case .unknown:
            0.58
        case .missing:
            0.12
        case .disabled:
            0
        case .error:
            0.25
        }
    }

    private func scoreCapability(
        _ provider: AgentProviderSnapshot,
        mode: AgentExecutionMode,
        promptSignals: PromptSignals
    ) -> Double {
        guard provider.supports(mode) else { return 0.08 }

        var score = 0.72
        if promptSignals.needsImplementation && provider.capabilities.contains("code-editing") {
            score += 0.12
        }
        if promptSignals.needsReview && provider.capabilities.contains("review") {
            score += 0.10
        }
        if promptSignals.needsDebugging && provider.capabilities.contains("debugging") {
            score += 0.10
        }
        if provider.capabilities.contains("local-workspace") {
            score += 0.06
        }
        return min(score, 1)
    }

    private func scoreSpeed(providerID: String, usage: UsageSnapshot?) -> Double {
        guard let usage else { return 0.65 }
        // Prefer measured per-run latency when we have it; otherwise fall
        // back to the session-time average and finally to a neutral default.
        let measured = usage.averageLatencySeconds
        let latency: Double
        if measured > 0 {
            latency = measured
        } else if usage.callsToday > 0 {
            latency = usage.sessionSecondsToday / Double(usage.callsToday)
        } else {
            return 0.65
        }
        guard latency > 0 else { return 0.65 }
        return max(0.2, 1 - min(latency / 900, 0.8))
    }

    private func estimateCost(prompt: String, usage: UsageSnapshot?, provider: AgentProviderSnapshot) -> Double {
        let approximateTokens = max(250, prompt.count / 4)
        let pressureMultiplier = 1 + (usage?.limitPressure ?? 0)
        let base = Double(approximateTokens) / 1_000_000
        let providerMultiplier = provider.identifier.contains("api") ? 2.0 : 0.4
        return (base * providerMultiplier * pressureMultiplier * 10).rounded(toPlaces: 4)
    }

    private func scoreCost(_ estimatedCost: Double) -> Double {
        switch estimatedCost {
        case 0...0.01: 1
        case 0.0101...0.05: 0.8
        case 0.0501...0.20: 0.55
        default: 0.35
        }
    }

    private func limitImpact(_ usage: UsageSnapshot?) -> String {
        guard let usage else { return "No observed usage; route from configured defaults." }
        switch usage.limitPressure {
        case 0..<0.35:
            return "Low pressure; budget available."
        case 0.35..<0.70:
            return "Moderate pressure; watch refresh window."
        default:
            return "High pressure; prefer another provider or wait for refresh."
        }
    }

    private func coordinationWarning(
        for mode: AgentExecutionMode,
        activeConflicts: [CoordinationEventSnapshot]
    ) -> String {
        guard mode == .implementation || mode == .repairDebug || mode == .commitPushCheckpoint else {
            return ""
        }
        guard !activeConflicts.isEmpty else { return "" }
        return "\(activeConflicts.count) active AgentNotes item(s) should be reviewed before dispatch."
    }

    private func rationale(
        provider: AgentProviderSnapshot,
        mode: AgentExecutionMode,
        availabilityScore: Double,
        capabilityScore: Double,
        limitScore: Double,
        accuracyScore: Double,
        coordinationWarning: String
    ) -> String {
        var parts = [
            "\(provider.displayName) scored \(availabilityScore.percentString) on availability",
            "\(capabilityScore.percentString) on \(mode.label) fit",
            "\(limitScore.percentString) on limit headroom",
            "\(accuracyScore.percentString) on observed accuracy",
        ]
        if !coordinationWarning.isEmpty {
            parts.append(coordinationWarning)
        }
        return parts.joined(separator: "; ")
    }
}

struct PromptSignals: Sendable {
    let needsImplementation: Bool
    let needsReview: Bool
    let needsDebugging: Bool
}

enum PromptSignalAnalyzer {
    static func analyze(_ prompt: String) -> PromptSignals {
        let lowercased = prompt.lowercased()
        return PromptSignals(
            needsImplementation: lowercased.contains("implement") ||
                lowercased.contains("build") ||
                lowercased.contains("fix") ||
                lowercased.contains("add"),
            needsReview: lowercased.contains("review") ||
                lowercased.contains("audit") ||
                lowercased.contains("inspect"),
            needsDebugging: lowercased.contains("debug") ||
                lowercased.contains("failing") ||
                lowercased.contains("broken") ||
                lowercased.contains("error")
        )
    }
}

enum UsageSnapshotBuilder {
    /// Build per-provider usage snapshots from the ledger and run outcomes.
    ///
    /// The policy parameter governs how raw counters become a `limitPressure`
    /// score and a refresh date. Pass `outcomes` to populate latency and
    /// success-rate fields; the parameter is optional so older call sites
    /// (e.g. tests that only care about cost/calls) still compile.
    static func build(
        from entries: [UsageLedgerEntry],
        outcomes: [RunOutcomeRecord] = [],
        providers: [AgentProviderProfile],
        policy: UsageLimitPolicy = .default,
        now: Date = Date()
    ) -> [UsageSnapshot] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)

        return providers.map { provider in
            let providerEntries = entries.filter {
                $0.providerID == provider.identifier && $0.createdAt >= startOfDay
            }
            let calls = providerEntries.reduce(0) { $0 + $1.callCount }
            let tokens = providerEntries.reduce(0) { $0 + $1.promptTokens + $1.completionTokens }
            let cost = providerEntries.reduce(0) { $0 + $1.estimatedCostUSD }
            let sessionSeconds = providerEntries.reduce(0) { $0 + $1.sessionSeconds }

            let providerOutcomes = outcomes.filter {
                $0.providerID == provider.identifier && $0.startedAt >= startOfDay
            }
            let succeeded = providerOutcomes.filter { $0.status == RunStatus.succeeded.rawValue }
            let failed = providerOutcomes.filter { $0.status == RunStatus.failed.rawValue }
            let cancelled = providerOutcomes.filter { $0.status == RunStatus.cancelled.rawValue }
            let succeededDurations = succeeded.map(\.durationSeconds).filter { $0 > 0 }
            let averageLatency: Double = succeededDurations.isEmpty
                ? 0
                : succeededDurations.reduce(0, +) / Double(succeededDurations.count)
            let outcomeDenominator = succeeded.count + failed.count
            let successRate: Double = outcomeDenominator == 0
                ? 1.0
                : Double(succeeded.count) / Double(outcomeDenominator)

            let pressure = policy.computePressure(
                forProvider: provider.identifier,
                calls: calls,
                tokens: tokens,
                cost: cost,
                sessionSeconds: sessionSeconds,
                now: now
            )

            return UsageSnapshot(
                providerID: provider.identifier,
                callsToday: calls,
                tokenCountToday: tokens,
                estimatedCostToday: cost,
                sessionSecondsToday: sessionSeconds,
                limitPressure: pressure.aggregateScore,
                refreshDate: pressure.nextRefresh,
                averageLatencySeconds: averageLatency,
                successRate: successRate,
                succeededRunsToday: succeeded.count,
                failedRunsToday: failed.count,
                cancelledRunsToday: cancelled.count,
                pressure: pressure
            )
        }
    }
}

enum AccuracySnapshotBuilder {
    static func build(from outcomes: [RunOutcomeRecord], providers: [AgentProviderProfile]) -> [AccuracySnapshot] {
        providers.map { provider in
            let providerOutcomes = outcomes.filter { $0.providerID == provider.identifier }
            let rated = providerOutcomes.compactMap { AccuracyRating(rawValue: $0.accuracyRating) }
            let total = rated.count
            let average = total == 0 ? 0.62 : rated.reduce(0) { $0 + $1.scoreContribution } / Double(total)
            let correct = rated.filter { $0 == .correct }.count
            let repair = rated.filter { [.minorFixNeeded, .debugNeeded, .recodeNeeded].contains($0) }.count
            let failure = rated.filter { [.brokeBuildOrTests, .abandoned].contains($0) }.count

            return AccuracySnapshot(
                providerID: provider.identifier,
                totalRatedRuns: total,
                averageScore: average,
                correctCount: correct,
                repairCount: repair,
                failureCount: failure
            )
        }
    }
}

struct DashboardHeatmapCell: Identifiable, Sendable {
    let id: UUID
    let providerID: String
    let providerName: String
    let metricName: String
    let value: Double
    let formattedValue: String
    let accessibilitySummary: String

    init(
        id: UUID = UUID(),
        providerID: String,
        providerName: String,
        metricName: String,
        value: Double,
        formattedValue: String,
        accessibilitySummary: String
    ) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.metricName = metricName
        self.value = value
        self.formattedValue = formattedValue
        self.accessibilitySummary = accessibilitySummary
    }
}

enum DashboardMetricFactory {
    /// Latency mapping: a 0s response is treated as a perfect 1.0 score, and
    /// a 10-minute response collapses to ~0. The dashboard cell still shows
    /// the raw seconds so users see the underlying signal.
    private static func latencyScore(seconds: Double) -> Double {
        guard seconds > 0 else { return 1.0 }
        return max(0, 1 - min(seconds / 600, 1))
    }

    static func heatmapCells(
        providers: [AgentProviderProfile],
        usage: [UsageSnapshot],
        accuracy: [AccuracySnapshot]
    ) -> [DashboardHeatmapCell] {
        let usageByProvider = Dictionary(uniqueKeysWithValues: usage.map { ($0.providerID, $0) })
        let accuracyByProvider = Dictionary(uniqueKeysWithValues: accuracy.map { ($0.providerID, $0) })

        return providers.flatMap { provider in
            let providerUsage = usageByProvider[provider.identifier]
            let providerAccuracy = accuracyByProvider[provider.identifier]
            let availability = ProviderAvailabilityState(rawValue: provider.installedState) == .available ? 1.0 : 0.25
            let limitHeadroom = max(0, 1 - (providerUsage?.limitPressure ?? 0.18))
            let accuracyScore = providerAccuracy?.averageScore ?? 0.62
            let costValue = providerUsage?.estimatedCostToday ?? 0
            let latencySeconds = providerUsage?.averageLatencySeconds ?? 0
            let successRate = providerUsage?.successRate ?? 1.0

            return [
                DashboardHeatmapCell(
                    providerID: provider.identifier,
                    providerName: provider.displayName,
                    metricName: "Availability",
                    value: availability,
                    formattedValue: availability.percentString,
                    accessibilitySummary: "\(provider.displayName) availability \(availability.percentString)"
                ),
                DashboardHeatmapCell(
                    providerID: provider.identifier,
                    providerName: provider.displayName,
                    metricName: "Limit Headroom",
                    value: limitHeadroom,
                    formattedValue: limitHeadroom.percentString,
                    accessibilitySummary: "\(provider.displayName) limit headroom \(limitHeadroom.percentString)"
                ),
                DashboardHeatmapCell(
                    providerID: provider.identifier,
                    providerName: provider.displayName,
                    metricName: "Accuracy",
                    value: accuracyScore,
                    formattedValue: accuracyScore.percentString,
                    accessibilitySummary: "\(provider.displayName) accuracy \(accuracyScore.percentString)"
                ),
                DashboardHeatmapCell(
                    providerID: provider.identifier,
                    providerName: provider.displayName,
                    metricName: "Latency",
                    value: latencyScore(seconds: latencySeconds),
                    formattedValue: latencySeconds > 0
                        ? String(format: "%.1fs", latencySeconds)
                        : "—",
                    accessibilitySummary: latencySeconds > 0
                        ? "\(provider.displayName) average latency \(String(format: "%.1f seconds", latencySeconds))"
                        : "\(provider.displayName) latency unavailable"
                ),
                DashboardHeatmapCell(
                    providerID: provider.identifier,
                    providerName: provider.displayName,
                    metricName: "Success",
                    value: successRate,
                    formattedValue: successRate.percentString,
                    accessibilitySummary: "\(provider.displayName) success rate \(successRate.percentString)"
                ),
                DashboardHeatmapCell(
                    providerID: provider.identifier,
                    providerName: provider.displayName,
                    metricName: "Cost",
                    value: min(costValue / 5, 1),
                    formattedValue: costValue.formatted(.currency(code: "USD")),
                    accessibilitySummary: "\(provider.displayName) estimated cost today \(costValue.formatted(.currency(code: "USD")))"
                ),
            ]
        }
    }
}

private extension Double {
    var percentString: String {
        formatted(.percent.precision(.fractionLength(0)))
    }

    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
