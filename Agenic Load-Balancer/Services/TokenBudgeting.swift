//
//  TokenBudgeting.swift
//  Agenic Load-Balancer
//
//  Sprint C: provider-neutral context estimates, preflight compaction,
//  transcript segmentation, and continuation prompt preparation.
//

import Foundation

enum TokenBudgetRisk: String, Sendable, Codable, Hashable {
    case low
    case elevated
    case high
    case overLimit

    var label: String {
        switch self {
        case .low: "Low"
        case .elevated: "Elevated"
        case .high: "High"
        case .overLimit: "Over limit"
        }
    }
}

struct TokenBudgetEstimate: Sendable, Codable, Hashable {
    var providerID: String
    var thresholdTokens: Int
    var providerContextWindowTokens: Int
    var userPromptTokens: Int
    var agentNotesTokens: Int
    var workspacePolicyTokens: Int
    var projectContextTokens: Int
    var standardOutputTokens: Int
    var standardErrorTokens: Int
    var cachedPromptTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int

    var totalInputTokens: Int {
        userPromptTokens + agentNotesTokens + workspacePolicyTokens + projectContextTokens
    }

    var totalObservedTokens: Int {
        totalInputTokens + standardOutputTokens + standardErrorTokens + outputTokens + reasoningTokens
    }

    var headroomTokens: Int {
        thresholdTokens - totalInputTokens
    }

    var risk: TokenBudgetRisk {
        guard thresholdTokens > 0 else { return .low }
        if totalInputTokens > thresholdTokens { return .overLimit }
        let ratio = Double(totalInputTokens) / Double(thresholdTokens)
        if ratio >= 0.90 { return .high }
        if ratio >= 0.70 { return .elevated }
        return .low
    }

    var needsCompaction: Bool {
        risk == .overLimit || risk == .high
    }

    var summary: String {
        let headroom = max(headroomTokens, 0)
        return "\(totalInputTokens.formatted()) input tokens estimated, \(headroom.formatted()) under the \(thresholdTokens.formatted()) token threshold."
    }

    var ledgerLimitWindow: String {
        "context:\(risk.rawValue):\(totalInputTokens)/\(thresholdTokens)"
    }
}

struct PreflightContextBudgetResult: Sendable, Hashable {
    var agentNotesExcerpt: String?
    var estimate: TokenBudgetEstimate
    var didCompact: Bool
    var compactionNote: String?
}

struct RunContinuationPlan: Sendable, Codable, Hashable {
    var reason: String
    var summary: String
    var prompt: String
    var estimatedResumeTokens: Int
    /// Sprint O.1: failure category that triggered the continuation, the
    /// chain depth this resume would be (0 = originating run, 1 = first
    /// resume, etc.), the parent runID (when known), and whether the policy
    /// keeps the resume behind a second approval tap. Defaults preserve
    /// Sprint C call sites that didn't pass these.
    var triggerCategory: String
    var chainDepth: Int
    var parentRunID: String?
    var requiresApproval: Bool
    /// Number of workspace source-file excerpts that were embedded in the
    /// resume prompt. Zero when no project root was available or no files
    /// matched the allowlist.
    var workspaceExcerptCount: Int

    init(
        reason: String,
        summary: String,
        prompt: String,
        estimatedResumeTokens: Int,
        triggerCategory: String = ContinuationTriggerCategory.unknown.rawValue,
        chainDepth: Int = 1,
        parentRunID: String? = nil,
        requiresApproval: Bool = true,
        workspaceExcerptCount: Int = 0
    ) {
        self.reason = reason
        self.summary = summary
        self.prompt = prompt
        self.estimatedResumeTokens = estimatedResumeTokens
        self.triggerCategory = triggerCategory
        self.chainDepth = chainDepth
        self.parentRunID = parentRunID
        self.requiresApproval = requiresApproval
        self.workspaceExcerptCount = workspaceExcerptCount
    }
}

enum TokenBudgetEstimator {
    static let defaultCharactersPerToken = 4

    static func providerContextWindowTokens(for providerID: String) -> Int {
        switch providerID {
        case "openai.codex": 128_000
        case "anthropic.claude-code": 200_000
        case "google.gemini-cli": 1_000_000
        case "github.copilot-cli": 64_000
        case "apple.foundation-models": 32_000
        default: 128_000
        }
    }

    static func effectiveThreshold(
        providerID: String,
        configuredThresholdTokens: Int,
        contextCompactionEnabled: Bool
    ) -> Int {
        let providerWindow = providerContextWindowTokens(for: providerID)
        guard contextCompactionEnabled else {
            return max(8_000, providerWindow)
        }
        let safeProviderBudget = max(8_000, Int(Double(providerWindow) * 0.82))
        return max(1_000, min(configuredThresholdTokens, safeProviderBudget))
    }

    static func estimatePreflight(
        userPrompt: String,
        agentNotesExcerpt: String?,
        workspacePolicy: String?,
        projectRootPath: String?,
        providerID: String,
        contextCompactionEnabled: Bool,
        thresholdTokens: Int
    ) -> TokenBudgetEstimate {
        let effectiveThreshold = effectiveThreshold(
            providerID: providerID,
            configuredThresholdTokens: thresholdTokens,
            contextCompactionEnabled: contextCompactionEnabled
        )
        return TokenBudgetEstimate(
            providerID: providerID,
            thresholdTokens: effectiveThreshold,
            providerContextWindowTokens: providerContextWindowTokens(for: providerID),
            userPromptTokens: estimateTokens(in: userPrompt),
            agentNotesTokens: estimateTokens(in: agentNotesExcerpt ?? ""),
            workspacePolicyTokens: estimateTokens(in: workspacePolicy ?? ""),
            projectContextTokens: estimateTokens(in: projectRootPath ?? ""),
            standardOutputTokens: 0,
            standardErrorTokens: 0,
            cachedPromptTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0
        )
    }

    static func estimateRun(
        plan: RunPlan,
        agentNotesExcerpt: String?,
        workspacePolicy: String?,
        projectRootPath: String?,
        standardOutput: String,
        standardError: String,
        cachedPromptTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningTokens: Int = 0
    ) -> TokenBudgetEstimate {
        var estimate = estimatePreflight(
            userPrompt: plan.prompt,
            agentNotesExcerpt: agentNotesExcerpt,
            workspacePolicy: workspacePolicy,
            projectRootPath: projectRootPath,
            providerID: plan.providerID,
            contextCompactionEnabled: plan.contextCompactionEnabled,
            thresholdTokens: plan.contextCompactionThresholdTokens
        )
        estimate.standardOutputTokens = estimateTokens(in: standardOutput)
        estimate.standardErrorTokens = estimateTokens(in: standardError)
        estimate.cachedPromptTokens = cachedPromptTokens
        estimate.outputTokens = outputTokens
        estimate.reasoningTokens = reasoningTokens
        return estimate
    }

    static func preparePreflightContext(
        userPrompt: String,
        agentNotesExcerpt: String?,
        workspacePolicy: String?,
        projectRootPath: String?,
        providerID: String,
        contextCompactionEnabled: Bool,
        thresholdTokens: Int
    ) -> PreflightContextBudgetResult {
        let originalEstimate = estimatePreflight(
            userPrompt: userPrompt,
            agentNotesExcerpt: agentNotesExcerpt,
            workspacePolicy: workspacePolicy,
            projectRootPath: projectRootPath,
            providerID: providerID,
            contextCompactionEnabled: contextCompactionEnabled,
            thresholdTokens: thresholdTokens
        )
        guard contextCompactionEnabled,
              let agentNotesExcerpt,
              !agentNotesExcerpt.isEmpty,
              originalEstimate.needsCompaction else {
            return PreflightContextBudgetResult(
                agentNotesExcerpt: agentNotesExcerpt,
                estimate: originalEstimate,
                didCompact: false,
                compactionNote: nil
            )
        }

        let reservedTokens = originalEstimate.userPromptTokens
            + originalEstimate.workspacePolicyTokens
            + originalEstimate.projectContextTokens
            + 768
        let targetAgentNotesTokens = max(256, originalEstimate.thresholdTokens - reservedTokens)
        let compacted = compact(
            agentNotesExcerpt,
            targetTokens: targetAgentNotesTokens,
            label: "AgentNotes preflight"
        )
        let compactedEstimate = estimatePreflight(
            userPrompt: userPrompt,
            agentNotesExcerpt: compacted,
            workspacePolicy: workspacePolicy,
            projectRootPath: projectRootPath,
            providerID: providerID,
            contextCompactionEnabled: contextCompactionEnabled,
            thresholdTokens: thresholdTokens
        )
        return PreflightContextBudgetResult(
            agentNotesExcerpt: compacted,
            estimate: compactedEstimate,
            didCompact: compacted != agentNotesExcerpt,
            compactionNote: "Compacted AgentNotes from \(originalEstimate.agentNotesTokens.formatted()) to \(compactedEstimate.agentNotesTokens.formatted()) estimated tokens before dispatch."
        )
    }

    static func makeContinuationPlan(
        plan: RunPlan,
        standardOutput: String,
        standardError: String,
        errorMessage: String,
        estimate: TokenBudgetEstimate
    ) -> RunContinuationPlan {
        makeContinuationPlan(
            plan: plan,
            standardOutput: standardOutput,
            standardError: standardError,
            errorMessage: errorMessage,
            estimate: estimate,
            triggerCategory: .unknown,
            chainDepth: 1,
            parentRunID: nil,
            requiresApproval: true,
            workspaceContext: nil
        )
    }

    /// Sprint O.1: chain-aware continuation prompt construction. Optional
    /// arguments default to the original Sprint C behaviour so existing
    /// callers keep compiling untouched.
    static func makeContinuationPlan(
        plan: RunPlan,
        standardOutput: String,
        standardError: String,
        errorMessage: String,
        estimate: TokenBudgetEstimate,
        triggerCategory: ContinuationTriggerCategory,
        chainDepth: Int,
        parentRunID: String?,
        requiresApproval: Bool,
        workspaceContext: WorkspaceSourceContext?
    ) -> RunContinuationPlan {
        let outputTail = compact(standardOutput, targetTokens: 900, label: "stdout tail")
        let errorTail = compact(standardError, targetTokens: 500, label: "stderr tail")
        let summary = """
        Previous \(plan.providerName) run (chain depth \(chainDepth)) stopped because \(errorMessage)
        Trigger category: \(triggerCategory.label)
        Estimated prompt pressure was \(estimate.totalInputTokens.formatted()) input tokens against a \(estimate.thresholdTokens.formatted()) token threshold.
        """
        let workspaceSection: String = {
            guard let workspaceContext, !workspaceContext.excerpts.isEmpty else {
                return ""
            }
            return """

            \(workspaceContext.formattedPromptFragment)
            """
        }()
        let prompt = """
        Continue the previous \(plan.mode.label) run safely.

        Context from Agenic Load-Balancer:
        \(summary)

        Original user goal:
        \(compact(plan.prompt, targetTokens: 1_500, label: "original prompt"))
        \(workspaceSection)
        Recent stdout:
        \(outputTail)

        Recent stderr:
        \(errorTail)

        Resume from the last coherent state, avoid repeating completed work, re-read AgentNotes if available, and stop if required project context is still missing or if this is the last allowed resume.
        """
        return RunContinuationPlan(
            reason: errorMessage,
            summary: summary,
            prompt: prompt,
            estimatedResumeTokens: estimateTokens(in: prompt),
            triggerCategory: triggerCategory.rawValue,
            chainDepth: chainDepth,
            parentRunID: parentRunID,
            requiresApproval: requiresApproval,
            workspaceExcerptCount: workspaceContext?.excerpts.count ?? 0
        )
    }

    /// Sprint O.1: top-level entry point used by the dispatcher. Consults
    /// `ProviderContinuationPolicy` to decide eligibility, computes the
    /// next chain depth, optionally pulls a deterministic workspace
    /// excerpt, and either prepares a `RunContinuationPlan` or returns a
    /// reason string explaining why no continuation will be offered.
    static func prepareContinuation(
        plan: RunPlan,
        parentRunID: String,
        parentChainDepth: Int,
        triggerCategory: ContinuationTriggerCategory,
        errorMessage: String,
        standardOutput: String,
        standardError: String,
        estimate: TokenBudgetEstimate,
        policy: ProviderContinuationPolicy,
        workspaceTargetTokens: Int = 1_200,
        clock: @Sendable () -> Date = Date.init
    ) -> ContinuationDecision {
        let nextChainDepth = parentChainDepth + 1
        guard policy.eligibleTriggers.contains(triggerCategory) else {
            return .notEligible(reason: "Provider policy excludes trigger \(triggerCategory.label).")
        }
        guard nextChainDepth <= policy.maxChainDepth else {
            return .notEligible(
                reason: "Chain depth \(nextChainDepth) would exceed policy cap (\(policy.maxChainDepth))."
            )
        }
        let workspaceContext = WorkspaceSourceSummarizer.summarize(
            projectRootPath: plan.projectRootPath,
            targetTotalTokens: workspaceTargetTokens,
            clock: clock
        )
        let continuationPlan = makeContinuationPlan(
            plan: plan,
            standardOutput: standardOutput,
            standardError: standardError,
            errorMessage: errorMessage,
            estimate: estimate,
            triggerCategory: triggerCategory,
            chainDepth: nextChainDepth,
            parentRunID: parentRunID,
            requiresApproval: !policy.allowsAutomaticResume,
            workspaceContext: workspaceContext
        )
        return .prepared(
            plan: continuationPlan,
            requiresApproval: !policy.allowsAutomaticResume,
            policy: policy
        )
    }

    static func estimateTokens(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return max(1, Int(ceil(Double(trimmed.count) / Double(defaultCharactersPerToken))))
    }

    static func compact(_ text: String, targetTokens: Int, label: String) -> String {
        let targetCharacters = max(512, targetTokens * defaultCharactersPerToken)
        guard text.count > targetCharacters else { return text }

        let marker = "[compacted \(label) to \(targetTokens.formatted()) estimated tokens from \(estimateTokens(in: text).formatted())]\n"
        let remaining = max(128, targetCharacters - marker.count - 32)
        let headCount = max(96, Int(Double(remaining) * 0.30))
        let tailCount = max(96, remaining - headCount)
        let head = String(text.prefix(headCount))
        let tail = String(text.suffix(tailCount))
        return marker + head + "\n...[middle omitted for context budget]...\n" + tail
    }
}

struct TranscriptSegmentDraft: Sendable, Hashable {
    var runID: String
    var providerID: String
    var projectID: String?
    var segmentIndex: Int
    var kind: String
    var text: String
    var tokenEstimate: Int
    var isCompacted: Bool
    var summary: String
    var createdAt: Date
}

enum RunTranscriptSegmenter {
    static func segments(
        runID: String,
        providerID: String,
        projectID: String?,
        logs: [RunDispatcher.LogLine],
        createdAt: Date,
        targetCharacters: Int = 4_000
    ) -> [TranscriptSegmentDraft] {
        let transcriptText = logs
            .filter { $0.kind == .stdout || $0.kind == .stderr }
            .map { "[\($0.kind.rawValue)] \($0.text)" }
            .joined(separator: "\n")
        guard !transcriptText.isEmpty else { return [] }

        let chunks = chunk(transcriptText, targetCharacters: targetCharacters)
        return chunks.enumerated().map { index, text in
            let compacted = text.count >= targetCharacters
            return TranscriptSegmentDraft(
                runID: runID,
                providerID: providerID,
                projectID: projectID,
                segmentIndex: index,
                kind: "mixed",
                text: text,
                tokenEstimate: TokenBudgetEstimator.estimateTokens(in: text),
                isCompacted: compacted,
                summary: "Transcript segment \(index + 1) of \(chunks.count)",
                createdAt: createdAt
            )
        }
    }

    private static func chunk(_ text: String, targetCharacters: Int) -> [String] {
        guard text.count > targetCharacters else { return [text] }
        var result: [String] = []
        var remainder = text[...]
        while !remainder.isEmpty {
            let end = remainder.index(
                remainder.startIndex,
                offsetBy: min(targetCharacters, remainder.count),
                limitedBy: remainder.endIndex
            ) ?? remainder.endIndex
            result.append(String(remainder[..<end]))
            remainder = remainder[end...]
        }
        return result
    }
}
