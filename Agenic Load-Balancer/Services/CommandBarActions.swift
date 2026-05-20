//
//  CommandBarActions.swift
//  Agenic Load-Balancer
//
//  Phase 7.3: shared action surface for the natural-language command bar.
//

import Foundation

enum CommandBarActionKind: String, CaseIterable, Sendable, Codable, Hashable {
    case rankAgents
    case dispatchRun
    case probeProviders
    case createSnapshot
    case reconcileAgentNotes
    case readDashboardMetrics
}

enum CommandBarApprovalRequirement: String, Sendable, Codable, Hashable {
    case none
    case userApprovalRequired
    case blockedByPolicy
}

struct CommandBarActionResult: Identifiable, Sendable, Codable, Hashable {
    let id: UUID
    var kind: CommandBarActionKind
    var title: String
    var summary: String
    var detailLines: [String]
    var approvalRequirement: CommandBarApprovalRequirement
    var approvalID: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: CommandBarActionKind,
        title: String,
        summary: String,
        detailLines: [String] = [],
        approvalRequirement: CommandBarApprovalRequirement = .none,
        approvalID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.detailLines = detailLines
        self.approvalRequirement = approvalRequirement
        self.approvalID = approvalID
        self.createdAt = createdAt
    }
}

struct CommandBarContext: Sendable {
    var prompt: String
    var mode: AgentExecutionMode
    var projectID: String?
    var projectName: String?
    var projectRootPath: String?
    var providers: [AgentProviderSnapshot]
    var usage: [UsageSnapshot]
    var accuracy: [AccuracySnapshot]
    var coordinationEvents: [CoordinationEventSnapshot]

    init(
        prompt: String,
        mode: AgentExecutionMode,
        projectID: String? = nil,
        projectName: String? = nil,
        projectRootPath: String? = nil,
        providers: [AgentProviderSnapshot],
        usage: [UsageSnapshot] = [],
        accuracy: [AccuracySnapshot] = [],
        coordinationEvents: [CoordinationEventSnapshot] = []
    ) {
        self.prompt = prompt
        self.mode = mode
        self.projectID = projectID
        self.projectName = projectName
        self.projectRootPath = projectRootPath
        self.providers = providers
        self.usage = usage
        self.accuracy = accuracy
        self.coordinationEvents = coordinationEvents
    }
}

enum CommandBarActionFormatter {
    static func format(_ result: CommandBarActionResult) -> String {
        var lines = [
            result.title,
            result.summary,
        ]
        lines.append(contentsOf: result.detailLines)
        switch result.approvalRequirement {
        case .none:
            break
        case .userApprovalRequired:
            lines.append("Approval required: \(result.approvalID ?? "pending")")
        case .blockedByPolicy:
            lines.append("Blocked by policy.")
        }
        return lines.joined(separator: "\n")
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}

actor CommandBarActionExecutor {
    private let routingEngine: RoutingEngine
    private let healthMonitor: ProviderHealthMonitor
    private let coordination: ProjectCoordinationActor

    init(
        routingEngine: RoutingEngine = AppServices.routingEngine,
        healthMonitor: ProviderHealthMonitor = AppServices.healthMonitor,
        coordination: ProjectCoordinationActor = AppServices.coordination
    ) {
        self.routingEngine = routingEngine
        self.healthMonitor = healthMonitor
        self.coordination = coordination
    }

    func rankAgents(context: CommandBarContext, limit: Int = 5) async -> CommandBarActionResult {
        let ranked = await routingEngine.rank(
            prompt: context.prompt,
            mode: context.mode,
            providers: context.providers,
            usage: context.usage,
            accuracy: context.accuracy,
            coordinationEvents: context.coordinationEvents
        )
        let boundedLimit = max(1, min(limit, 10))
        let limited = Array(ranked.prefix(boundedLimit))
        let summary = limited.first.map {
            "\($0.providerName) leads at \(CommandBarActionFormatter.percent($0.totalScore))."
        } ?? "No enabled providers were available."
        return CommandBarActionResult(
            kind: .rankAgents,
            title: "Ranked \(limited.count) agent(s)",
            summary: summary,
            detailLines: limited.map { score in
                "\(score.providerName): \(CommandBarActionFormatter.percent(score.totalScore)) - \(score.rationale)"
            }
        )
    }

    func dispatchRunDraft(context: CommandBarContext, providerID: String? = nil) async -> CommandBarActionResult {
        let ranked = await routingEngine.rank(
            prompt: context.prompt,
            mode: context.mode,
            providers: context.providers,
            usage: context.usage,
            accuracy: context.accuracy,
            coordinationEvents: context.coordinationEvents
        )
        let selected = providerID.flatMap { id in
            ranked.first { $0.providerID == id }
        } ?? ranked.first

        guard let selected else {
            return CommandBarActionResult(
                kind: .dispatchRun,
                title: "No dispatch target",
                summary: "No enabled provider can run this request.",
                approvalRequirement: .blockedByPolicy
            )
        }

        return CommandBarActionResult(
            kind: .dispatchRun,
            title: "Approve dispatch to \(selected.providerName)",
            summary: "Prepared \(context.mode.label) run for \(selected.providerName).",
            detailLines: [
                selected.rationale,
                selected.limitImpact,
                "Estimated cost: \(CommandBarActionFormatter.currency(selected.estimatedCostUSD))",
            ],
            approvalRequirement: .userApprovalRequired,
            approvalID: "dispatch:\(selected.providerID):\(UUID().uuidString)"
        )
    }

    func probeProviders(context: CommandBarContext, providerID: String? = nil) async -> CommandBarActionResult {
        let targets = providerID.flatMap { id in
            context.providers.filter { $0.identifier == id }
        } ?? context.providers

        guard !targets.isEmpty else {
            return CommandBarActionResult(
                kind: .probeProviders,
                title: "No providers matched",
                summary: providerID.map { "No provider matched \($0)." } ?? "No providers are configured.",
                approvalRequirement: .blockedByPolicy
            )
        }

        var lines: [String] = []
        for provider in targets {
            let snapshot = await healthMonitor.probe(provider: provider)
            let version = snapshot.detectedVersion.map { " (\($0))" } ?? ""
            lines.append("\(provider.displayName): \(snapshot.availabilityState.rawValue)\(version) - \(snapshot.message)")
        }

        return CommandBarActionResult(
            kind: .probeProviders,
            title: "Provider probe complete",
            summary: "Checked \(targets.count) provider(s).",
            detailLines: lines
        )
    }

    func createSnapshotDraft(scope: String) -> CommandBarActionResult {
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandBarActionResult(
            kind: .createSnapshot,
            title: "Approve snapshot",
            summary: "Create a checksummed snapshot archive for \(normalizedScope.isEmpty ? "the current project" : normalizedScope).",
            approvalRequirement: .userApprovalRequired,
            approvalID: "snapshot:\(UUID().uuidString)"
        )
    }

    func reconcileAgentNotesDraft(context: CommandBarContext) async -> CommandBarActionResult {
        guard let projectName = context.projectName,
              let rootPath = context.projectRootPath else {
            return CommandBarActionResult(
                kind: .reconcileAgentNotes,
                title: "AgentNotes unavailable",
                summary: "Select a project with a root path before reconciling AgentNotes.",
                approvalRequirement: .blockedByPolicy
            )
        }

        do {
            let result = try await coordination.reconcile(
                projectName: projectName,
                rootPath: rootPath,
                events: context.coordinationEvents
            )
            return CommandBarActionResult(
                kind: .reconcileAgentNotes,
                title: "AgentNotes reconciliation",
                summary: Self.describe(result.state),
                detailLines: [result.fileURL.path],
                approvalRequirement: result.requiresAttention ? .userApprovalRequired : .none,
                approvalID: result.requiresAttention ? "agentnotes:\(UUID().uuidString)" : nil
            )
        } catch {
            return CommandBarActionResult(
                kind: .reconcileAgentNotes,
                title: "AgentNotes reconciliation failed",
                summary: error.localizedDescription,
                approvalRequirement: .blockedByPolicy
            )
        }
    }

    func readDashboardMetrics(context: CommandBarContext, providerID: String? = nil) -> CommandBarActionResult {
        let usage = providerID.flatMap { id in
            context.usage.filter { $0.providerID == id }
        } ?? context.usage
        let accuracy = providerID.flatMap { id in
            context.accuracy.filter { $0.providerID == id }
        } ?? context.accuracy

        let usageLines = usage.map { snapshot in
            "\(snapshot.providerID): pressure \(CommandBarActionFormatter.percent(snapshot.limitPressure)), success \(CommandBarActionFormatter.percent(snapshot.successRate)), latency \(Int(snapshot.averageLatencySeconds))s, cost \(CommandBarActionFormatter.currency(snapshot.estimatedCostToday))"
        }
        let accuracyLines = accuracy.map { snapshot in
            "\(snapshot.providerID): accuracy \(CommandBarActionFormatter.percent(snapshot.averageScore)) across \(snapshot.totalRatedRuns) rated run(s)"
        }
        let lines = usageLines + accuracyLines

        return CommandBarActionResult(
            kind: .readDashboardMetrics,
            title: "Dashboard metrics",
            summary: "Read \(lines.count) dashboard signal(s).",
            detailLines: lines.isEmpty ? ["No dashboard metrics are available yet."] : lines
        )
    }

    private static func describe(_ state: AgentNotesReconciliation.State) -> String {
        switch state {
        case .fileMissing:
            return "AgentNotes.md is missing; regeneration can create it."
        case .fileMatches:
            return "AgentNotes.md matches the SwiftData coordination ledger."
        case .fileDiverged(let localChecksum, let generatedChecksum):
            return "AgentNotes.md diverged. Local \(localChecksum.prefix(12)), generated \(generatedChecksum.prefix(12))."
        case .conflictMarkers(let detail):
            return detail
        }
    }
}
