//
//  NaturalLanguageCommandBar.swift
//  Agenic Load-Balancer
//
//  Phase 7.3: natural-language command-bar model with Foundation Models
//  tool calling and deterministic fallback behavior.
//

import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum CommandBarError: Error, Sendable, LocalizedError, Equatable {
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "Command bar unavailable: \(reason)"
        case .failed(let reason):
            return "Command bar failed: \(reason)"
        }
    }
}

@MainActor
@Observable
final class NaturalLanguageCommandBarModel {
    enum State: Sendable, Equatable {
        case idle
        case responding
        case completed(String)
        case failed(String)

        var isResponding: Bool {
            if case .responding = self { return true }
            return false
        }
    }

    private(set) var state: State = .idle
    private(set) var lastResult: String = ""

    @ObservationIgnored private let availabilityChecker: any FoundationModelsAvailabilityChecking
    @ObservationIgnored private let executor: CommandBarActionExecutor

    init(
        availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker(),
        executor: CommandBarActionExecutor = CommandBarActionExecutor()
    ) {
        self.availabilityChecker = availabilityChecker
        self.executor = executor
    }

    func submit(prompt: String, context: CommandBarContext) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .responding

        let availability = availabilityChecker.currentAvailability()
        Task {
            do {
                let output: String
                if availability.isAvailable {
                    output = try await Self.respondWithFoundationModels(
                        prompt: trimmed,
                        context: context,
                        executor: executor
                    )
                } else {
                    output = await Self.deterministicFallback(
                        prompt: trimmed,
                        context: context,
                        executor: executor,
                        unavailableReason: availability.message
                    )
                }
                await MainActor.run {
                    self.lastResult = output
                    self.state = .completed(output)
                }
            } catch {
                await MainActor.run {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    nonisolated static func deterministicFallback(
        prompt: String,
        context: CommandBarContext,
        executor: CommandBarActionExecutor,
        unavailableReason: String
    ) async -> String {
        let lower = prompt.lowercased()
        let result: CommandBarActionResult
        if lower.contains("probe") || lower.contains("availability") || lower.contains("health") {
            result = await executor.probeProviders(context: context)
        } else if lower.contains("snapshot") {
            result = await executor.createSnapshotDraft(scope: context.projectName ?? "current project")
        } else if lower.contains("reconcile") || lower.contains("agentnotes") || lower.contains("agent notes") {
            result = await executor.reconcileAgentNotesDraft(context: context)
        } else if lower.contains("metric") || lower.contains("dashboard") || lower.contains("usage") {
            result = await executor.readDashboardMetrics(context: context)
        } else if lower.contains("dispatch") || lower.contains("run") {
            result = await executor.dispatchRunDraft(context: context)
        } else {
            result = await executor.rankAgents(context: context)
        }
        return "Foundation Models unavailable: \(unavailableReason)\n" + CommandBarActionFormatter.format(result)
    }

    nonisolated static func respondWithFoundationModels(
        prompt: String,
        context: CommandBarContext,
        executor: CommandBarActionExecutor
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let contextProvider: @Sendable () async -> CommandBarContext = { context }
            let tools: [any Tool] = [
                RankAgentsTool(executor: executor, contextProvider: contextProvider),
                DispatchRunTool(executor: executor, contextProvider: contextProvider),
                ProbeProvidersTool(executor: executor, contextProvider: contextProvider),
                CreateSnapshotTool(executor: executor),
                ReconcileAgentNotesTool(executor: executor, contextProvider: contextProvider),
                ReadDashboardMetricsTool(executor: executor, contextProvider: contextProvider),
            ]
            let session = LanguageModelSession(
                tools: tools,
                instructions: Instructions {
                    "You operate the Agenic Load-Balancer command bar."
                    "Use tools for current app data and app actions."
                    "Never claim a draft action has already executed."
                    "Say when user approval is required."
                    "Keep the response concise."
                }
            )
            let response = try await session.respond(to: prompt)
            return response.content
        }
        throw CommandBarError.unavailable(FoundationModelsAvailability.frameworkUnavailable.message)
        #else
        throw CommandBarError.unavailable(FoundationModelsAvailability.frameworkUnavailable.message)
        #endif
    }
}
