//
//  ProviderProbeTelemetry.swift
//  Agenic Load-Balancer
//
//  Sprint D: normalize provider probe/auth/limit signals so routing and the
//  command bar explain live provider state with the same vocabulary.
//

import Foundation

enum ProviderProbeAuthStatus: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case accountSignedIn
    case apiKeyPresent
    case customProfile
    case unauthenticated
    case notRequired
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accountSignedIn: "Account signed in"
        case .apiKeyPresent: "API key present"
        case .customProfile: "Custom profile"
        case .unauthenticated: "Login required"
        case .notRequired: "No auth required"
        case .unknown: "Auth unknown"
        }
    }
}
enum ProviderLimitProbeStatus: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case healthy
    case subscriptionLimited
    case quotaLimited
    case rateLimited
    case contextLimited
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .healthy: "Limits healthy"
        case .subscriptionLimited: "Subscription limited"
        case .quotaLimited: "Quota limited"
        case .rateLimited: "Rate limited"
        case .contextLimited: "Context limited"
        case .unknown: "Limits unknown"
        }
    }

    var isLimiting: Bool {
        switch self {
        case .subscriptionLimited, .quotaLimited, .rateLimited, .contextLimited:
            return true
        case .healthy, .unknown:
            return false
        }
    }
}

struct ProviderProbeReport: Sendable, Hashable, Identifiable {
    let providerID: String
    let authStatus: ProviderProbeAuthStatus
    let limitStatus: ProviderLimitProbeStatus
    let reliabilityScore: Double?
    let summary: String
    let detailLines: [String]

    var id: String { providerID }
}

enum ProviderProbeClassifier {
    static func authStatus(
        provider: AgentProviderSnapshot,
        recipe: ProviderAuthRecipe = ProviderAuthRecipe.recipe(for: ""),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProviderProbeAuthStatus {
        if provider.identifier == "apple.foundation-models" {
            return .notRequired
        }

        switch provider.authState {
        case .authenticated:
            return .accountSignedIn
        case .custom:
            return .customProfile
        case .unauthenticated, .needsToken, .browserLoginRequired:
            return .unauthenticated
        case .unknown:
            break
        }

        let resolvedRecipe = recipe.providerID.isEmpty
            ? ProviderAuthRecipe.recipe(for: provider.identifier)
            : recipe
        if resolvedRecipe.apiKeyEnvironmentVariables.contains(where: { key in
            environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }) {
            return .apiKeyPresent
        }

        return .unknown
    }

    static func limitStatus(
        from text: String,
        usage: UsageSnapshot? = nil,
        reliability: ProviderReliabilitySnapshot? = nil
    ) -> ProviderLimitProbeStatus {
        let detected = limitStatus(fromOutput: text)
        if detected != .unknown {
            return detected
        }
        if let usage, usage.limitPressure >= 0.88 {
            return .quotaLimited
        }
        if let reliability {
            if reliability.rateLimitedRunCount > 0 {
                return .rateLimited
            }
            if reliability.quotaLimitedRunCount > 0 {
                return .quotaLimited
            }
            if reliability.contextLimitedRunCount > 0 {
                return .contextLimited
            }
        }
        if let usage, usage.limitPressure < 0.55 {
            return .healthy
        }
        return .unknown
    }

    static func limitStatus(fromOutput text: String) -> ProviderLimitProbeStatus {
        let lowercased = text.lowercased()
        guard !lowercased.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unknown
        }

        if lowercased.contains("context window") ||
            lowercased.contains("context length") ||
            lowercased.contains("maximum context") ||
            lowercased.contains("too many tokens") ||
            lowercased.contains("token limit") {
            return .contextLimited
        }

        if lowercased.contains("rate limit") ||
            lowercased.contains("too many requests") ||
            lowercased.contains("http 429") ||
            lowercased.contains(" 429") {
            return .rateLimited
        }

        if lowercased.contains("quota") ||
            lowercased.contains("usage limit") ||
            lowercased.contains("limit exceeded") ||
            lowercased.contains("exceeded your current") {
            return .quotaLimited
        }

        if lowercased.contains("subscription") ||
            lowercased.contains("upgrade") ||
            lowercased.contains("plan limit") ||
            lowercased.contains("billing") {
            return .subscriptionLimited
        }

        return .unknown
    }

    static func report(
        provider: AgentProviderSnapshot,
        health: ProviderHealthSnapshot,
        usage: UsageSnapshot?,
        reliability: ProviderReliabilitySnapshot?
    ) -> ProviderProbeReport {
        let auth = health.authStatus == .unknown
            ? authStatus(provider: provider)
            : health.authStatus
        let limit = health.limitStatus == .unknown
            ? limitStatus(from: health.message, usage: usage, reliability: reliability)
            : health.limitStatus
        let reliabilityText = reliability.map {
            "Reliability \($0.reliabilityScore.formatted(.percent.precision(.fractionLength(0)))) over \($0.recentRunCount) recent run(s)."
        }

        var details = [
            "Availability: \(health.availabilityState.rawValue)",
            "Auth: \(auth.label)",
            "Limits: \(limit.label)",
        ]
        if let version = health.detectedVersion {
            details.append("Version: \(version)")
        }
        if let reliabilityText {
            details.append(reliabilityText)
        }
        details.append(contentsOf: health.detailLines)

        return ProviderProbeReport(
            providerID: provider.identifier,
            authStatus: auth,
            limitStatus: limit,
            reliabilityScore: reliability?.reliabilityScore,
            summary: "\(auth.label); \(limit.label)",
            detailLines: details
        )
    }
}
