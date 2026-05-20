//
//  RoutingTieBreaker.swift
//  Agenic Load-Balancer
//
//  Phase 7.5: optional Foundation Models tie-breaks for close provider scores.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct RoutingTieBreak: Sendable, Codable, Hashable {
    var selectedProviderID: String
    var confidence: Double
    var reason: String
    var cautions: [String]
}

struct RoutingTieBreakInput: Sendable {
    var prompt: String
    var mode: AgentExecutionMode
    var candidates: [RoutingScoreBreakdown]
    var usage: [UsageSnapshot]
    var accuracy: [AccuracySnapshot]
    var coordinationEvents: [CoordinationEventSnapshot]
}

struct RoutingRecommendation: Sendable, Hashable {
    var ranked: [RoutingScoreBreakdown]
    var tieBreak: RoutingTieBreak?

    init(
        ranked: [RoutingScoreBreakdown] = [],
        tieBreak: RoutingTieBreak? = nil
    ) {
        self.ranked = ranked
        self.tieBreak = tieBreak
    }

    var selected: RoutingScoreBreakdown? {
        guard let tieBreak else { return ranked.first }
        return ranked.first { $0.providerID == tieBreak.selectedProviderID } ?? ranked.first
    }
}

enum RoutingTieBreakerError: Error, Sendable, LocalizedError, Equatable {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "Routing tie-breaker unavailable: \(reason)"
        }
    }
}

protocol RoutingTieBreaking: Sendable {
    func breakTie(input: RoutingTieBreakInput) async throws -> RoutingTieBreak
}

struct NoopRoutingTieBreaker: RoutingTieBreaking {
    let reason: String

    init(reason: String = "Apple Foundation Models is not available on this device.") {
        self.reason = reason
    }

    func breakTie(input: RoutingTieBreakInput) async throws -> RoutingTieBreak {
        guard let first = input.candidates.first else {
            throw RoutingTieBreakerError.unavailable(reason)
        }
        return RoutingTieBreak(
            selectedProviderID: first.providerID,
            confidence: 0,
            reason: reason,
            cautions: ["Deterministic score order preserved."]
        )
    }
}

struct ScriptedRoutingTieBreaker: RoutingTieBreaking {
    let result: RoutingTieBreak

    func breakTie(input _: RoutingTieBreakInput) async throws -> RoutingTieBreak {
        result
    }
}

enum RoutingTieBreakerFactory {
    static func makeDefault(
        availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker()
    ) -> any RoutingTieBreaking {
        let availability = availabilityChecker.currentAvailability()
        guard availability.isAvailable else {
            return NoopRoutingTieBreaker(reason: availability.message)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return LiveFoundationModelsRoutingTieBreaker()
        }
        return NoopRoutingTieBreaker(reason: FoundationModelsAvailability.frameworkUnavailable.message)
        #else
        return NoopRoutingTieBreaker(reason: FoundationModelsAvailability.frameworkUnavailable.message)
        #endif
    }
}

actor RoutingRecommendationCoordinator {
    private let routingEngine: RoutingEngine
    private let tieBreaker: any RoutingTieBreaking

    init(
        routingEngine: RoutingEngine = AppServices.routingEngine,
        tieBreaker: any RoutingTieBreaking = RoutingTieBreakerFactory.makeDefault()
    ) {
        self.routingEngine = routingEngine
        self.tieBreaker = tieBreaker
    }

    func recommend(
        prompt: String,
        mode: AgentExecutionMode,
        providers: [AgentProviderSnapshot],
        usage: [UsageSnapshot],
        accuracy: [AccuracySnapshot],
        coordinationEvents: [CoordinationEventSnapshot]
    ) async -> RoutingRecommendation {
        let ranked = await routingEngine.rank(
            prompt: prompt,
            mode: mode,
            providers: providers,
            usage: usage,
            accuracy: accuracy,
            coordinationEvents: coordinationEvents
        )
        let candidates = RoutingEngine.closeScoreCandidates(from: ranked)
        guard candidates.count > 1 else {
            return RoutingRecommendation(ranked: ranked)
        }

        let input = RoutingTieBreakInput(
            prompt: prompt,
            mode: mode,
            candidates: candidates,
            usage: usage,
            accuracy: accuracy,
            coordinationEvents: coordinationEvents
        )
        guard let tieBreak = try? await tieBreaker.breakTie(input: input),
              candidates.contains(where: { $0.providerID == tieBreak.selectedProviderID }) else {
            return RoutingRecommendation(ranked: ranked)
        }
        return RoutingRecommendation(ranked: ranked, tieBreak: tieBreak)
    }
}

#if canImport(FoundationModels)

@available(macOS 26.0, *)
@Generable
struct GeneratedRoutingTieBreak: Sendable {
    @Guide(description: "Identifier of the best provider from the candidate list.")
    var selectedProviderID: String

    @Guide(description: "Confidence from 0.0 through 1.0.")
    var confidence: Double

    @Guide(description: "Short reason grounded in the candidate scores and prompt.")
    var reason: String

    @Guide(description: "Risks or caveats to show beside the recommendation.")
    var cautions: [String]

    var asTieBreak: RoutingTieBreak {
        RoutingTieBreak(
            selectedProviderID: selectedProviderID,
            confidence: max(0, min(confidence, 1)),
            reason: reason,
            cautions: cautions
        )
    }
}

@available(macOS 26.0, *)
struct LiveFoundationModelsRoutingTieBreaker: RoutingTieBreaking {
    init() {}

    func breakTie(input: RoutingTieBreakInput) async throws -> RoutingTieBreak {
        let session = LanguageModelSession(
            instructions: Instructions {
                "Choose one provider only from the candidate IDs."
                "Use deterministic scores as the source of truth."
                "Prefer the provider best fit for the prompt only when scores are close."
                "Do not invent provider IDs, metrics, commits, files, or validation evidence."
            }
        )
        let response = try await session.respond(
            to: Self.prompt(input: input),
            generating: GeneratedRoutingTieBreak.self,
            options: GenerationOptions(sampling: .greedy)
        )
        return response.content.asTieBreak
    }

    static func prompt(input: RoutingTieBreakInput) -> String {
        """
        Mode: \(input.mode.label)

        User prompt:
        \(input.prompt)

        Close-score candidates:
        \(candidateText(input.candidates))

        Usage:
        \(usageText(input.usage))

        Accuracy:
        \(accuracyText(input.accuracy))

        Active coordination events:
        \(coordinationText(input.coordinationEvents))
        """
    }

    private static func candidateText(_ candidates: [RoutingScoreBreakdown]) -> String {
        candidates.map { candidate in
            [
                "id=\(candidate.providerID)",
                "name=\(candidate.providerName)",
                "total=\(candidate.totalScore.formatted(.number.precision(.fractionLength(3))))",
                "availability=\(candidate.availabilityScore.formatted(.number.precision(.fractionLength(2))))",
                "capability=\(candidate.capabilityScore.formatted(.number.precision(.fractionLength(2))))",
                "limit=\(candidate.limitScore.formatted(.number.precision(.fractionLength(2))))",
                "accuracy=\(candidate.accuracyScore.formatted(.number.precision(.fractionLength(2))))",
                "speed=\(candidate.speedScore.formatted(.number.precision(.fractionLength(2))))",
                "cost=\(candidate.costScore.formatted(.number.precision(.fractionLength(2))))",
                "rationale=\(candidate.rationale)",
                "limitImpact=\(candidate.limitImpact)",
                "coordinationWarning=\(candidate.coordinationWarning)",
            ].joined(separator: " | ")
        }
        .joined(separator: "\n")
    }

    private static func usageText(_ usage: [UsageSnapshot]) -> String {
        guard !usage.isEmpty else { return "No usage snapshots." }
        return usage.map { snapshot in
            "\(snapshot.providerID): calls=\(snapshot.callsToday), pressure=\(snapshot.limitPressure), cost=\(snapshot.estimatedCostToday), latency=\(snapshot.averageLatencySeconds), success=\(snapshot.successRate)"
        }
        .joined(separator: "\n")
    }

    private static func accuracyText(_ accuracy: [AccuracySnapshot]) -> String {
        guard !accuracy.isEmpty else { return "No accuracy snapshots." }
        return accuracy.map { snapshot in
            "\(snapshot.providerID): average=\(snapshot.averageScore), rated=\(snapshot.totalRatedRuns), repair=\(snapshot.repairCount), failure=\(snapshot.failureCount)"
        }
        .joined(separator: "\n")
    }

    private static func coordinationText(_ events: [CoordinationEventSnapshot]) -> String {
        let active = events.filter { event in
            CoordinationStatus.isActiveForPreflight(event.status)
        }
        guard !active.isEmpty else { return "No active coordination events." }
        return active.prefix(12).map { event in
            "\(event.status): \(event.title) - \(event.detail)"
        }
        .joined(separator: "\n")
    }
}

#endif
