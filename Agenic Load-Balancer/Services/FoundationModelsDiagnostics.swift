//
//  FoundationModelsDiagnostics.swift
//  Agenic Load-Balancer
//
//  Sprint B: live Apple Foundation Models verification for command-bar
//  tools, guided run summaries, and close-score routing tie-breaks.
//

import Foundation

enum FoundationModelsDiagnosticProbeKind: String, CaseIterable, Identifiable, Sendable {
    case availability
    case commandBarMetrics
    case runSummary
    case routingTieBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .availability: "Availability"
        case .commandBarMetrics: "Command bar metrics"
        case .runSummary: "Run summary"
        case .routingTieBreak: "Routing tie-break"
        }
    }
}

enum FoundationModelsDiagnosticProbeStatus: String, Sendable {
    case succeeded
    case skipped
    case failed

    var label: String {
        switch self {
        case .succeeded: "Succeeded"
        case .skipped: "Skipped"
        case .failed: "Failed"
        }
    }
}

struct FoundationModelsDiagnosticProbeResult: Identifiable, Sendable {
    let id: UUID
    var kind: FoundationModelsDiagnosticProbeKind
    var status: FoundationModelsDiagnosticProbeStatus
    var summary: String
    var detail: String
    var durationSeconds: Double
    var observedAt: Date

    init(
        id: UUID = UUID(),
        kind: FoundationModelsDiagnosticProbeKind,
        status: FoundationModelsDiagnosticProbeStatus,
        summary: String,
        detail: String,
        durationSeconds: Double = 0,
        observedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.summary = summary
        self.detail = detail
        self.durationSeconds = durationSeconds
        self.observedAt = observedAt
    }
}

struct FoundationModelsDiagnosticReport: Identifiable, Sendable {
    let id: UUID
    var startedAt: Date
    var finishedAt: Date
    var availability: FoundationModelsAvailability
    var probes: [FoundationModelsDiagnosticProbeResult]

    init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        availability: FoundationModelsAvailability,
        probes: [FoundationModelsDiagnosticProbeResult]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.availability = availability
        self.probes = probes
    }

    var statusSummary: String {
        let failures = probes.filter { $0.status == .failed }.count
        let skipped = probes.filter { $0.status == .skipped }.count
        let succeeded = probes.filter { $0.status == .succeeded }.count

        if failures > 0 {
            return "\(failures) failed, \(succeeded) succeeded, \(skipped) skipped."
        }
        if skipped > 0 {
            return "\(succeeded) succeeded, \(skipped) skipped because Foundation Models is unavailable."
        }
        return "All \(succeeded) diagnostics succeeded."
    }

    var hasFailures: Bool {
        probes.contains { $0.status == .failed }
    }

    static func uiTestingFixture(now: Date = Date(timeIntervalSince1970: 1_780_000_000)) -> FoundationModelsDiagnosticReport {
        FoundationModelsDiagnosticReport(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000F0A1") ?? UUID(),
            startedAt: now.addingTimeInterval(-6),
            finishedAt: now,
            availability: .available,
            probes: [
                FoundationModelsDiagnosticProbeResult(
                    id: UUID(uuidString: "00000000-0000-0000-0000-00000000F0A2") ?? UUID(),
                    kind: .availability,
                    status: .succeeded,
                    summary: "Fixture availability succeeded",
                    detail: "Apple Foundation Models is available on this UI-test fixture.",
                    durationSeconds: 0.08,
                    observedAt: now
                ),
                FoundationModelsDiagnosticProbeResult(
                    id: UUID(uuidString: "00000000-0000-0000-0000-00000000F0A3") ?? UUID(),
                    kind: .commandBarMetrics,
                    status: .succeeded,
                    summary: "Metrics tool answered",
                    detail: "Command-bar metrics routed through deterministic fixture data.",
                    durationSeconds: 0.12,
                    observedAt: now
                ),
                FoundationModelsDiagnosticProbeResult(
                    id: UUID(uuidString: "00000000-0000-0000-0000-00000000F0A4") ?? UUID(),
                    kind: .runSummary,
                    status: .skipped,
                    summary: "Summary skipped",
                    detail: "Skipped in fixture so the visual matrix captures mixed diagnostic tones.",
                    durationSeconds: 0,
                    observedAt: now
                ),
                FoundationModelsDiagnosticProbeResult(
                    id: UUID(uuidString: "00000000-0000-0000-0000-00000000F0A5") ?? UUID(),
                    kind: .routingTieBreak,
                    status: .failed,
                    summary: "Tie-break refused",
                    detail: "Fixture refusal keeps the diagnostic failure path visible without calling the live model.",
                    durationSeconds: 0.14,
                    observedAt: now
                ),
            ]
        )
    }
}

protocol FoundationModelsDiagnosticsRunning: Sendable {
    func run() async -> FoundationModelsDiagnosticReport
}

struct FoundationModelsDiagnosticsRunner: FoundationModelsDiagnosticsRunning {
    typealias CommandBarResponder = @Sendable (
        _ prompt: String,
        _ context: CommandBarContext,
        _ executor: CommandBarActionExecutor
    ) async throws -> String

    private let availabilityChecker: any FoundationModelsAvailabilityChecking
    private let commandBarExecutor: CommandBarActionExecutor
    private let commandBarResponder: CommandBarResponder
    private let runSummarizer: any RunSummarizing
    private let tieBreaker: any RoutingTieBreaking

    init(
        availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker(),
        commandBarExecutor: CommandBarActionExecutor = CommandBarActionExecutor(),
        commandBarResponder: @escaping CommandBarResponder = { prompt, context, executor in
            try await NaturalLanguageCommandBarModel.respondWithFoundationModels(
                prompt: prompt,
                context: context,
                executor: executor
            )
        },
        runSummarizer: (any RunSummarizing)? = nil,
        tieBreaker: (any RoutingTieBreaking)? = nil
    ) {
        self.availabilityChecker = availabilityChecker
        self.commandBarExecutor = commandBarExecutor
        self.commandBarResponder = commandBarResponder
        self.runSummarizer = runSummarizer ?? RunSummarizerFactory.makeDefault(
            availabilityChecker: availabilityChecker
        )
        self.tieBreaker = tieBreaker ?? RoutingTieBreakerFactory.makeDefault(
            availabilityChecker: availabilityChecker
        )
    }

    func run() async -> FoundationModelsDiagnosticReport {
        let startedAt = Date()
        let availability = availabilityChecker.currentAvailability()
        var probes = [
            FoundationModelsDiagnosticProbeResult(
                kind: .availability,
                status: .succeeded,
                summary: availability.isAvailable ? "Available" : "Unavailable",
                detail: availability.message
            ),
        ]

        guard availability.isAvailable else {
            probes.append(contentsOf: Self.liveProbeKinds.map { kind in
                FoundationModelsDiagnosticProbeResult(
                    kind: kind,
                    status: .skipped,
                    summary: "Live probe skipped",
                    detail: availability.message
                )
            })
            return FoundationModelsDiagnosticReport(
                startedAt: startedAt,
                finishedAt: Date(),
                availability: availability,
                probes: probes
            )
        }

        probes.append(
            await timeProbe(kind: .commandBarMetrics) {
                let output = try await commandBarResponder(
                    "Read dashboard metrics for the configured providers and return one concise status.",
                    Self.commandBarDiagnosticContext,
                    commandBarExecutor
                )
                return Self.compact(output)
            }
        )

        probes.append(
            await timeProbe(kind: .runSummary) {
                let summary = try await runSummarizer.summarize(input: Self.runSummaryDiagnosticInput)
                return "\(summary.oneLineDescription) (\(summary.suggestedAccuracyRating.rawValue))"
            }
        )

        probes.append(
            await timeProbe(kind: .routingTieBreak) {
                let tieBreak = try await tieBreaker.breakTie(input: Self.routingTieBreakDiagnosticInput)
                return "\(tieBreak.selectedProviderID) at \(Self.percent(tieBreak.confidence)): \(tieBreak.reason)"
            }
        )

        return FoundationModelsDiagnosticReport(
            startedAt: startedAt,
            finishedAt: Date(),
            availability: availability,
            probes: probes
        )
    }

    private func timeProbe(
        kind: FoundationModelsDiagnosticProbeKind,
        operation: @escaping @Sendable () async throws -> String
    ) async -> FoundationModelsDiagnosticProbeResult {
        let startedAt = Date()
        do {
            let detail = try await operation()
            return FoundationModelsDiagnosticProbeResult(
                kind: kind,
                status: .succeeded,
                summary: "Live probe succeeded",
                detail: detail,
                durationSeconds: Date().timeIntervalSince(startedAt)
            )
        } catch {
            return FoundationModelsDiagnosticProbeResult(
                kind: kind,
                status: .failed,
                summary: Self.classify(error),
                detail: Self.errorDetail(error),
                durationSeconds: Date().timeIntervalSince(startedAt)
            )
        }
    }

    private static let liveProbeKinds: [FoundationModelsDiagnosticProbeKind] = [
        .commandBarMetrics,
        .runSummary,
        .routingTieBreak,
    ]

    private static var commandBarDiagnosticContext: CommandBarContext {
        CommandBarContext(
            prompt: "Inspect dashboard metrics for live Foundation Models diagnostics.",
            mode: .recommendOnly,
            projectID: "diagnostic-project",
            projectName: "FoundationModelsDiagnostic",
            projectRootPath: nil,
            providers: diagnosticProviders,
            usage: diagnosticUsage,
            accuracy: diagnosticAccuracy,
            coordinationEvents: []
        )
    }

    private static var runSummaryDiagnosticInput: RunSummaryInput {
        RunSummaryInput(
            prompt: "Summarize a successful diagnostics dry run.",
            providerID: FoundationModelsAdapter.catalogProviderID,
            providerName: "Apple Foundation Models",
            mode: .recommendOnly,
            exitCode: 0,
            durationSeconds: 1.25,
            standardOutput: "Diagnostics checked command-bar metrics, generated a summary, and selected a tie-break provider.",
            standardError: ""
        )
    }

    private static var routingTieBreakDiagnosticInput: RoutingTieBreakInput {
        RoutingTieBreakInput(
            prompt: "Pick the safer provider for a read-only dashboard metrics request.",
            mode: .recommendOnly,
            candidates: [
                RoutingScoreBreakdown(
                    providerID: "diagnostic.alpha",
                    providerName: "Diagnostic Alpha",
                    mode: .recommendOnly,
                    totalScore: 0.884,
                    availabilityScore: 1,
                    capabilityScore: 0.88,
                    limitScore: 0.98,
                    accuracyScore: 0.62,
                    speedScore: 0.86,
                    costScore: 1,
                    rationale: "Fast local metrics fit with low pressure.",
                    estimatedCostUSD: 0,
                    limitImpact: "Low pressure.",
                    coordinationWarning: ""
                ),
                RoutingScoreBreakdown(
                    providerID: "diagnostic.beta",
                    providerName: "Diagnostic Beta",
                    mode: .recommendOnly,
                    totalScore: 0.872,
                    availabilityScore: 1,
                    capabilityScore: 0.88,
                    limitScore: 1,
                    accuracyScore: 0.64,
                    speedScore: 0.70,
                    costScore: 1,
                    rationale: "Slightly higher accuracy with slower response.",
                    estimatedCostUSD: 0,
                    limitImpact: "Budget available.",
                    coordinationWarning: ""
                ),
            ],
            usage: diagnosticUsage,
            accuracy: diagnosticAccuracy,
            reliability: [],
            coordinationEvents: []
        )
    }

    private static let diagnosticProviders: [AgentProviderSnapshot] = [
        AgentProviderSnapshot(
            identifier: "diagnostic.alpha",
            displayName: "Diagnostic Alpha",
            binaryName: "diagnostic-alpha",
            installCommand: "",
            verificationCommand: "",
            supportedExecutionModes: AgentExecutionMode.allCases.map(\.rawValue).joined(separator: ","),
            capabilities: "review,local-workspace,metrics",
            installedState: .available,
            authState: .authenticated,
            isEnabled: true
        ),
        AgentProviderSnapshot(
            identifier: "diagnostic.beta",
            displayName: "Diagnostic Beta",
            binaryName: "diagnostic-beta",
            installCommand: "",
            verificationCommand: "",
            supportedExecutionModes: AgentExecutionMode.allCases.map(\.rawValue).joined(separator: ","),
            capabilities: "review,local-workspace,metrics",
            installedState: .available,
            authState: .authenticated,
            isEnabled: true
        ),
    ]

    private static let diagnosticUsage: [UsageSnapshot] = [
        UsageSnapshot(
            providerID: "diagnostic.alpha",
            callsToday: 3,
            tokenCountToday: 1_200,
            estimatedCostToday: 0,
            sessionSecondsToday: 42,
            limitPressure: 0.08,
            refreshDate: Date(),
            averageLatencySeconds: 1.4,
            successRate: 1
        ),
        UsageSnapshot(
            providerID: "diagnostic.beta",
            callsToday: 2,
            tokenCountToday: 900,
            estimatedCostToday: 0,
            sessionSecondsToday: 60,
            limitPressure: 0.02,
            refreshDate: Date(),
            averageLatencySeconds: 2.4,
            successRate: 0.98
        ),
    ]

    private static let diagnosticAccuracy: [AccuracySnapshot] = [
        AccuracySnapshot(
            providerID: "diagnostic.alpha",
            totalRatedRuns: 8,
            averageScore: 0.62,
            correctCount: 5,
            repairCount: 2,
            failureCount: 1
        ),
        AccuracySnapshot(
            providerID: "diagnostic.beta",
            totalRatedRuns: 9,
            averageScore: 0.64,
            correctCount: 6,
            repairCount: 2,
            failureCount: 1
        ),
    ]

    private static func compact(_ value: String, maxCharacters: Int = 260) -> String {
        guard value.count > maxCharacters else { return value }
        return String(value.prefix(maxCharacters)) + "..."
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private static func classify(_ error: Error) -> String {
        let detail = errorDetail(error).localizedLowercase
        if detail.contains("unsupported") && (detail.contains("locale") || detail.contains("language")) {
            return "Unsupported locale or language"
        }
        if detail.contains("refus") || detail.contains("safety") || detail.contains("guardrail") {
            return "Request refused by model policy"
        }
        if detail.contains("context") {
            return "Exceeded model context window"
        }
        return "Live probe failed"
    }

    private static func errorDetail(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
