//
//  CommandBarTools.swift
//  Agenic Load-Balancer
//
//  Phase 7.3: Foundation Models tool wrappers around command-bar actions.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
struct RankAgentsTool: Tool {
    let description = "Ranks available coding agents for the current prompt."
    let executor: CommandBarActionExecutor
    let contextProvider: @Sendable () async -> CommandBarContext

    @Generable
    struct Arguments {
        @Guide(description: "Maximum number of agents to return. Use a value from 1 through 10.")
        var limit: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let context = await contextProvider()
        let result = await executor.rankAgents(context: context, limit: arguments.limit)
        return CommandBarActionFormatter.format(result)
    }
}

@available(macOS 26.0, *)
struct DispatchRunTool: Tool {
    let description = "Prepares a provider run for user approval; it does not start the run by itself."
    let executor: CommandBarActionExecutor
    let contextProvider: @Sendable () async -> CommandBarContext

    @Generable
    struct Arguments {
        @Guide(description: "Provider identifier to dispatch, or empty to use the top-ranked provider.")
        var providerID: String
    }

    func call(arguments: Arguments) async throws -> String {
        let context = await contextProvider()
        let result = await executor.dispatchRunDraft(
            context: context,
            providerID: arguments.providerID.isEmpty ? nil : arguments.providerID
        )
        return CommandBarActionFormatter.format(result)
    }
}

@available(macOS 26.0, *)
struct ProbeProvidersTool: Tool {
    let description = "Probes provider installation, authentication, and on-device availability state."
    let executor: CommandBarActionExecutor
    let contextProvider: @Sendable () async -> CommandBarContext

    @Generable
    struct Arguments {
        @Guide(description: "Provider identifier to probe, or empty to probe every provider.")
        var providerID: String
    }

    func call(arguments: Arguments) async throws -> String {
        let context = await contextProvider()
        let result = await executor.probeProviders(
            context: context,
            providerID: arguments.providerID.isEmpty ? nil : arguments.providerID
        )
        return CommandBarActionFormatter.format(result)
    }
}

@available(macOS 26.0, *)
struct CreateSnapshotTool: Tool {
    let description = "Prepares a checksummed snapshot action for user approval."
    let executor: CommandBarActionExecutor

    @Generable
    struct Arguments {
        @Guide(description: "Snapshot scope label, such as full project or current project.")
        var scope: String
    }

    func call(arguments: Arguments) async throws -> String {
        let result = await executor.createSnapshotDraft(scope: arguments.scope)
        return CommandBarActionFormatter.format(result)
    }
}

@available(macOS 26.0, *)
struct ReconcileAgentNotesTool: Tool {
    let description = "Checks AgentNotes against the coordination ledger and prepares reconciliation for approval."
    let executor: CommandBarActionExecutor
    let contextProvider: @Sendable () async -> CommandBarContext

    @Generable
    struct Arguments {
        @Guide(description: "Use true to reconcile the selected project AgentNotes file.")
        var reconcileSelectedProject: Bool
    }

    func call(arguments _: Arguments) async throws -> String {
        let context = await contextProvider()
        let result = await executor.reconcileAgentNotesDraft(context: context)
        return CommandBarActionFormatter.format(result)
    }
}

@available(macOS 26.0, *)
struct ReadDashboardMetricsTool: Tool {
    let description = "Reads current provider usage, limit, success, latency, cost, and accuracy dashboard metrics."
    let executor: CommandBarActionExecutor
    let contextProvider: @Sendable () async -> CommandBarContext

    @Generable
    struct Arguments {
        @Guide(description: "Provider identifier to filter by, or empty for all providers.")
        var providerID: String
    }

    func call(arguments: Arguments) async throws -> String {
        let context = await contextProvider()
        let result = await executor.readDashboardMetrics(
            context: context,
            providerID: arguments.providerID.isEmpty ? nil : arguments.providerID
        )
        return CommandBarActionFormatter.format(result)
    }
}
#endif
