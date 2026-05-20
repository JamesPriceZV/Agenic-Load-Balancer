//
//  AgentNotesIntelligence.swift
//  Agenic Load-Balancer
//
//  Phase 7.4: prompt-relevant AgentNotes preflight summaries and
//  AI-assisted reconciliation proposals.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AgentNotesPreflightSummary: Sendable, Codable, Hashable {
    var relevantActiveClaims: [String]
    var blockingConflicts: [String]
    var suggestedClaim: String
    var promptInjectionText: String
}

struct AgentNotesMergeProposal: Sendable, Codable, Hashable {
    var mergedContent: String
    var retainedLocalLines: [String]
    var retainedGeneratedLines: [String]
    var unresolvedConflicts: [String]
    var explanation: String
}

enum AgentNotesPreflightFilter {
    static func activeCoordinationText(from agentNotes: String) -> String {
        let parsed = parseEventBlocks(from: agentNotes)
        guard !parsed.blocks.isEmpty else { return agentNotes }

        let activeBlocks = parsed.blocks.filter { block in
            CoordinationStatus.isActiveForPreflight(block.status) &&
                !isStaleCancelledDispatchBlock(block)
        }
        let renderedActive = activeBlocks.isEmpty
            ? "- No active coordination blockers."
            : activeBlocks.map(\.text).joined(separator: "\n")
        return headerPrefix(from: parsed.header) +
            "\n\n## Active Work\n" +
            renderedActive
    }

    private struct EventBlock {
        var status: String
        var text: String
    }

    private static func parseEventBlocks(from text: String) -> (header: String, blocks: [EventBlock]) {
        let lines = text.components(separatedBy: .newlines)
        var header: [String] = []
        var blocks: [EventBlock] = []
        var current: [String] = []
        var currentStatus: String?

        func flushCurrent() {
            guard let currentStatus else { return }
            blocks.append(EventBlock(status: currentStatus, text: current.joined(separator: "\n")))
            current.removeAll()
        }

        for line in lines {
            if let status = statusPrefix(in: line) {
                flushCurrent()
                currentStatus = status
                current = [line]
            } else if currentStatus != nil {
                current.append(line)
            } else {
                header.append(line)
            }
        }
        flushCurrent()
        return (header.joined(separator: "\n"), blocks)
    }

    private static func headerPrefix(from header: String) -> String {
        var prefix = header
        if let activeRange = prefix.range(of: "## Active Work") {
            prefix = String(prefix[..<activeRange.lowerBound])
        }
        if let historyRange = prefix.range(of: "## History") {
            prefix = String(prefix[..<historyRange.lowerBound])
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func statusPrefix(in line: String) -> String? {
        guard line.hasPrefix("- ["),
              let close = line.firstIndex(of: "]")
        else { return nil }
        let start = line.index(line.startIndex, offsetBy: 3)
        guard start <= close else { return nil }
        return String(line[start..<close])
    }

    private static func isStaleCancelledDispatchBlock(_ block: EventBlock) -> Bool {
        guard block.status == CoordinationStatus.blocked.rawValue else { return false }
        let text = block.text.localizedLowercase
        return text.contains("phase 2 / dispatch") &&
            (text.contains("cancelled") || text.contains("canceled"))
    }
}

enum AgentNotesIntelligenceError: Error, Sendable, LocalizedError, Equatable {
    case unavailable(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "AgentNotes intelligence unavailable: \(reason)"
        case .generationFailed(let reason):
            return "AgentNotes intelligence failed: \(reason)"
        }
    }
}

protocol AgentNotesIntelligencing: Sendable {
    func summarizePreflight(
        agentNotes: String,
        prompt: String,
        mode: AgentExecutionMode
    ) async throws -> AgentNotesPreflightSummary

    func proposeMerge(
        localContent: String,
        generatedContent: String
    ) async throws -> AgentNotesMergeProposal
}

struct NoopAgentNotesIntelligence: AgentNotesIntelligencing {
    let reason: String

    init(reason: String = "Apple Foundation Models is not available on this device.") {
        self.reason = reason
    }

    func summarizePreflight(
        agentNotes _: String,
        prompt _: String,
        mode _: AgentExecutionMode
    ) async throws -> AgentNotesPreflightSummary {
        throw AgentNotesIntelligenceError.unavailable(reason)
    }

    func proposeMerge(
        localContent _: String,
        generatedContent _: String
    ) async throws -> AgentNotesMergeProposal {
        throw AgentNotesIntelligenceError.unavailable(reason)
    }
}

struct ScriptedAgentNotesIntelligence: AgentNotesIntelligencing {
    var summary: AgentNotesPreflightSummary
    var proposal: AgentNotesMergeProposal

    func summarizePreflight(
        agentNotes _: String,
        prompt _: String,
        mode _: AgentExecutionMode
    ) async throws -> AgentNotesPreflightSummary {
        summary
    }

    func proposeMerge(
        localContent _: String,
        generatedContent _: String
    ) async throws -> AgentNotesMergeProposal {
        proposal
    }
}

enum AgentNotesIntelligenceFactory {
    static func makeDefault(
        availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker()
    ) -> any AgentNotesIntelligencing {
        let availability = availabilityChecker.currentAvailability()
        guard availability.isAvailable else {
            return NoopAgentNotesIntelligence(reason: availability.message)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return LiveFoundationModelsAgentNotesIntelligence()
        }
        return NoopAgentNotesIntelligence(reason: FoundationModelsAvailability.frameworkUnavailable.message)
        #else
        return NoopAgentNotesIntelligence(reason: FoundationModelsAvailability.frameworkUnavailable.message)
        #endif
    }
}

#if canImport(FoundationModels)

@available(macOS 26.0, *)
@Generable
struct GeneratedAgentNotesPreflightSummary: Sendable {
    @Guide(description: "Active AgentNotes claims relevant to the user's prompt.")
    var relevantActiveClaims: [String]

    @Guide(description: "Blocking conflicts the user or agent must resolve before dispatch.")
    var blockingConflicts: [String]

    @Guide(description: "A concise claim line the next agent should record before editing.")
    var suggestedClaim: String

    @Guide(description: "Short text safe to inject into an agent prompt.")
    var promptInjectionText: String

    var asSummary: AgentNotesPreflightSummary {
        AgentNotesPreflightSummary(
            relevantActiveClaims: relevantActiveClaims,
            blockingConflicts: blockingConflicts,
            suggestedClaim: suggestedClaim,
            promptInjectionText: promptInjectionText
        )
    }
}

@available(macOS 26.0, *)
@Generable
struct GeneratedAgentNotesMergeProposal: Sendable {
    @Guide(description: "Full merged AgentNotes content preserving both local and generated facts.")
    var mergedContent: String

    @Guide(description: "Important local lines retained in the merge.")
    var retainedLocalLines: [String]

    @Guide(description: "Important generated lines retained in the merge.")
    var retainedGeneratedLines: [String]

    @Guide(description: "Conflicts that cannot be resolved safely.")
    var unresolvedConflicts: [String]

    @Guide(description: "Concise explanation of the merge strategy.")
    var explanation: String

    var asProposal: AgentNotesMergeProposal {
        AgentNotesMergeProposal(
            mergedContent: mergedContent,
            retainedLocalLines: retainedLocalLines,
            retainedGeneratedLines: retainedGeneratedLines,
            unresolvedConflicts: unresolvedConflicts,
            explanation: explanation
        )
    }
}

@available(macOS 26.0, *)
struct LiveFoundationModelsAgentNotesIntelligence: AgentNotesIntelligencing {
    init() {}

    func summarizePreflight(
        agentNotes: String,
        prompt: String,
        mode: AgentExecutionMode
    ) async throws -> AgentNotesPreflightSummary {
        let session = LanguageModelSession(
            instructions: Instructions {
                "Summarize AgentNotes only for the current prompt."
                "Prefer active claims, conflicts, blockers, and the exact next claim."
                "Ignore completed, checkpointed, cancelled, and stale cancelled dispatch history."
                "Do not invent commits, tests, file state, owners, or validation evidence."
            }
        )
        do {
            let response = try await session.respond(
                to: Self.preflightPrompt(agentNotes: agentNotes, prompt: prompt, mode: mode),
                generating: GeneratedAgentNotesPreflightSummary.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content.asSummary
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw AgentNotesIntelligenceError.generationFailed(detail)
        }
    }

    func proposeMerge(
        localContent: String,
        generatedContent: String
    ) async throws -> AgentNotesMergeProposal {
        let session = LanguageModelSession(
            instructions: Instructions {
                "Merge AgentNotes content losslessly."
                "Preserve chronological facts, validation evidence, blockers, and conflict markers."
                "List unresolved conflicts instead of guessing."
            }
        )
        do {
            let response = try await session.respond(
                to: Self.mergePrompt(localContent: localContent, generatedContent: generatedContent),
                generating: GeneratedAgentNotesMergeProposal.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content.asProposal
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw AgentNotesIntelligenceError.generationFailed(detail)
        }
    }

    static func preflightPrompt(agentNotes: String, prompt: String, mode: AgentExecutionMode) -> String {
        """
        Mode: \(mode.label)

        User prompt:
        \(prompt)

        AgentNotes content:
        \(truncate(agentNotes, limit: 24_000))
        """
    }

    static func mergePrompt(localContent: String, generatedContent: String) -> String {
        """
        Local AgentNotes:
        \(truncate(localContent, limit: 24_000))

        Generated AgentNotes:
        \(truncate(generatedContent, limit: 24_000))
        """
    }

    static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return "[truncated to last \(limit) chars]\n" + String(text.suffix(limit))
    }
}

#endif
