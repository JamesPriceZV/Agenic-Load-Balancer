//
//  UsageLimitPolicy.swift
//  Agenic Load-Balancer
//
//  Created by Claude on 5/5/26.
//
//  Phase 4: pull manual quotas, refresh windows, and pressure scoring out of
//  the hard-coded heuristic that previously lived inside `UsageSnapshotBuilder`
//  and into a dedicated `UsageLimitPolicy` value type. The policy is Sendable
//  so it can be passed to actors (the routing engine) and SwiftUI views
//  alike. Default quotas are seeded per provider family so the dashboard has
//  meaningful pressure values out of the box; user-tunable persistence lands
//  in Phase 5.
//

import Foundation

/// Window over which a provider's quota counters reset.
enum RefreshWindow: String, Sendable, Codable, CaseIterable, Hashable {
    case hourly
    case daily
    case rollingTwentyFourHours
    case weekly
    case manual

    /// Human-readable label for the dashboard.
    var label: String {
        switch self {
        case .hourly: "Hourly"
        case .daily: "Daily"
        case .rollingTwentyFourHours: "Rolling 24h"
        case .weekly: "Weekly"
        case .manual: "Manual"
        }
    }

    /// Date at which the window will next reset, given a reference moment.
    /// Returns `nil` for `.manual` (user-driven reset).
    func nextRefresh(after reference: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .hourly:
            let comps = calendar.dateComponents([.year, .month, .day, .hour], from: reference)
            guard let topOfHour = calendar.date(from: comps) else { return nil }
            return calendar.date(byAdding: .hour, value: 1, to: topOfHour)
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference))
        case .rollingTwentyFourHours:
            return calendar.date(byAdding: .hour, value: 24, to: reference)
        case .weekly:
            var components = DateComponents()
            components.weekday = 2 // next Monday
            components.hour = 0
            components.minute = 0
            return calendar.nextDate(
                after: reference,
                matching: components,
                matchingPolicy: .nextTime
            )
        case .manual:
            return nil
        }
    }
}

/// A per-provider quota envelope. Counters are interpreted against the
/// provider's configured `refreshWindow`.
struct UsageQuota: Sendable, Codable, Hashable {
    let providerID: String
    let maxCallsPerWindow: Int
    let maxTokensPerWindow: Int
    let maxSessionSecondsPerWindow: Double
    let softCostBudgetUSD: Double
    let refreshWindow: RefreshWindow
    let notes: String

    init(
        providerID: String,
        maxCallsPerWindow: Int,
        maxTokensPerWindow: Int,
        maxSessionSecondsPerWindow: Double,
        softCostBudgetUSD: Double,
        refreshWindow: RefreshWindow,
        notes: String = ""
    ) {
        self.providerID = providerID
        self.maxCallsPerWindow = maxCallsPerWindow
        self.maxTokensPerWindow = maxTokensPerWindow
        self.maxSessionSecondsPerWindow = maxSessionSecondsPerWindow
        self.softCostBudgetUSD = softCostBudgetUSD
        self.refreshWindow = refreshWindow
        self.notes = notes
    }
}

/// Computed pressure for a single provider at a moment in time. All `*Usage`
/// values are clamped to `0...1`; `aggregateScore` is a weighted combination
/// usable as a single dashboard metric.
struct UsagePressure: Sendable, Hashable {
    let providerID: String
    let callsUsage: Double
    let tokensUsage: Double
    let costUsage: Double
    let sessionUsage: Double
    let aggregateScore: Double
    let nextRefresh: Date?
    let quota: UsageQuota
}

/// Sendable, immutable policy bundle. Hold one as a `static let` (`.default`)
/// for the seeded catalog values; replace via `with(quota:)` when the user
/// tunes a provider in Settings (Phase 5).
struct UsageLimitPolicy: Sendable, Hashable {
    let quotas: [String: UsageQuota]
    let defaultQuota: UsageQuota

    init(quotas: [String: UsageQuota], defaultQuota: UsageQuota) {
        self.quotas = quotas
        self.defaultQuota = defaultQuota
    }

    /// Look up the quota for a provider, falling back to `defaultQuota` if
    /// nothing has been configured yet.
    func quota(forProvider providerID: String) -> UsageQuota {
        quotas[providerID] ?? defaultQuota
    }

    /// Return a new policy with `quota` applied (replacing any existing entry
    /// for the same provider).
    func with(quota: UsageQuota) -> UsageLimitPolicy {
        var updated = quotas
        updated[quota.providerID] = quota
        return UsageLimitPolicy(quotas: updated, defaultQuota: defaultQuota)
    }

    /// Compute pressure given raw usage counters. The aggregate weights calls
    /// most heavily because a call exhaustion is the most disruptive failure
    /// mode in practice; tokens come second; cost and session time are
    /// secondary signals.
    func computePressure(
        forProvider providerID: String,
        calls: Int,
        tokens: Int,
        cost: Double,
        sessionSeconds: Double,
        now: Date = Date()
    ) -> UsagePressure {
        let quota = quota(forProvider: providerID)

        let callsUsage = quota.maxCallsPerWindow > 0
            ? min(1.0, Double(calls) / Double(quota.maxCallsPerWindow))
            : 0
        let tokensUsage = quota.maxTokensPerWindow > 0
            ? min(1.0, Double(tokens) / Double(quota.maxTokensPerWindow))
            : 0
        let costUsage = quota.softCostBudgetUSD > 0
            ? min(1.0, cost / quota.softCostBudgetUSD)
            : 0
        let sessionUsage = quota.maxSessionSecondsPerWindow > 0
            ? min(1.0, sessionSeconds / quota.maxSessionSecondsPerWindow)
            : 0

        let aggregate =
            callsUsage * 0.40 +
            tokensUsage * 0.35 +
            costUsage * 0.15 +
            sessionUsage * 0.10

        return UsagePressure(
            providerID: providerID,
            callsUsage: callsUsage,
            tokensUsage: tokensUsage,
            costUsage: costUsage,
            sessionUsage: sessionUsage,
            aggregateScore: min(1.0, aggregate),
            nextRefresh: quota.refreshWindow.nextRefresh(after: now),
            quota: quota
        )
    }

    static let `default`: UsageLimitPolicy = .seeded()

    /// Seed defaults that approximate published or community-reported limits
    /// for each provider family. These are intentionally conservative so the
    /// pressure heatmap surfaces something useful even before the user tunes
    /// per-provider quotas.
    static func seeded() -> UsageLimitPolicy {
        let fallback = UsageQuota(
            providerID: "default",
            maxCallsPerWindow: 50,
            maxTokensPerWindow: 250_000,
            maxSessionSecondsPerWindow: 3600 * 4,
            softCostBudgetUSD: 5.0,
            refreshWindow: .daily,
            notes: "Default quota applied to providers without an explicit policy."
        )
        let entries: [UsageQuota] = [
            UsageQuota(
                providerID: "openai.codex",
                maxCallsPerWindow: 200,
                maxTokensPerWindow: 1_000_000,
                maxSessionSecondsPerWindow: 3600 * 6,
                softCostBudgetUSD: 20.0,
                refreshWindow: .daily,
                notes: "Approximation of subscription/API mix."
            ),
            UsageQuota(
                providerID: "anthropic.claude-code",
                maxCallsPerWindow: 200,
                maxTokensPerWindow: 1_000_000,
                maxSessionSecondsPerWindow: 3600 * 6,
                softCostBudgetUSD: 20.0,
                refreshWindow: .daily,
                notes: "Approximation of Claude subscription/API mix."
            ),
            UsageQuota(
                providerID: "github.copilot-cli",
                maxCallsPerWindow: 500,
                maxTokensPerWindow: 0,
                maxSessionSecondsPerWindow: 3600 * 8,
                softCostBudgetUSD: 0,
                refreshWindow: .daily,
                notes: "Subscription model; tokens not tracked, cost is flat."
            ),
            UsageQuota(
                providerID: "google.gemini-cli",
                maxCallsPerWindow: 200,
                maxTokensPerWindow: 1_000_000,
                maxSessionSecondsPerWindow: 3600 * 6,
                softCostBudgetUSD: 15.0,
                refreshWindow: .daily,
                notes: "Defaults inspired by Gemini API tiers."
            ),
            UsageQuota(
                providerID: "cursor.agent",
                maxCallsPerWindow: 200,
                maxTokensPerWindow: 600_000,
                maxSessionSecondsPerWindow: 3600 * 6,
                softCostBudgetUSD: 15.0,
                refreshWindow: .daily,
                notes: "Per-account subscription model."
            ),
            UsageQuota(
                providerID: "kiro.cli",
                maxCallsPerWindow: 150,
                maxTokensPerWindow: 400_000,
                maxSessionSecondsPerWindow: 3600 * 4,
                softCostBudgetUSD: 8.0,
                refreshWindow: .daily,
                notes: "Defaults reflect Builder ID / IAM hybrid limits."
            ),
            UsageQuota(
                providerID: "qwen.code",
                maxCallsPerWindow: 200,
                maxTokensPerWindow: 800_000,
                maxSessionSecondsPerWindow: 3600 * 4,
                softCostBudgetUSD: 6.0,
                refreshWindow: .daily,
                notes: "Defaults for Qwen API/Coding Plan."
            ),
            UsageQuota(
                providerID: "mistral.vibe",
                maxCallsPerWindow: 150,
                maxTokensPerWindow: 500_000,
                maxSessionSecondsPerWindow: 3600 * 4,
                softCostBudgetUSD: 8.0,
                refreshWindow: .daily,
                notes: "Defaults reflect Mistral Vibe terminal pricing posture."
            ),
            UsageQuota(
                providerID: "opencode.cli",
                maxCallsPerWindow: 250,
                maxTokensPerWindow: 1_500_000,
                maxSessionSecondsPerWindow: 3600 * 6,
                softCostBudgetUSD: 25.0,
                refreshWindow: .daily,
                notes: "Multi-provider proxy; budget is aggregate."
            ),
            UsageQuota(
                providerID: "apple.foundation-models",
                maxCallsPerWindow: 5_000,
                maxTokensPerWindow: 10_000_000,
                maxSessionSecondsPerWindow: 3600 * 24,
                softCostBudgetUSD: 0,
                refreshWindow: .rollingTwentyFourHours,
                notes: "On-device Apple Intelligence — generous defaults reflect zero per-call cost; throughput is bounded by device thermal/power state."
            ),
            UsageQuota(
                providerID: "deepseek.api",
                maxCallsPerWindow: 1000,
                maxTokensPerWindow: 5_000_000,
                maxSessionSecondsPerWindow: 3600 * 12,
                softCostBudgetUSD: 50.0,
                refreshWindow: .daily,
                notes: "API-only provider; generous defaults reflecting low per-token cost."
            ),
        ]
        let map = Dictionary(uniqueKeysWithValues: entries.map { ($0.providerID, $0) })
        return UsageLimitPolicy(quotas: map, defaultQuota: fallback)
    }
}
