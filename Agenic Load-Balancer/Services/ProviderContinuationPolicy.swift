//
//  ProviderContinuationPolicy.swift
//  Agenic Load-Balancer
//
//  Sprint O.1: provider-specific continuation loops. Encodes per-provider
//  rules for whether a follow-up run after a context-overflow / quota /
//  structured failure / nested non-zero exit can be auto-prepared, whether
//  it still requires approval, and how deep the continuation chain may go
//  before the dispatcher stops generating further resume prompts.
//
//  The policy itself is deterministic and Sendable so it composes safely
//  with the actor-isolated dispatcher. It never mutates SwiftData by
//  itself; the dispatcher and outcome sheet decide what to persist and what
//  to surface for approval.
//

import Foundation

/// Why a run finished in a state that *might* warrant a continuation.
/// Mirrors `ProviderFailureClassifier` categories with a single explicit
/// "unknown" fallback so policy callers never crash on a new error string.
enum ContinuationTriggerCategory: String, Sendable, Codable, Hashable, CaseIterable {
    case contextOverflow
    case quotaOrRateLimit
    case structuredFailure
    case nestedNonZeroExit
    case unknown

    var label: String {
        switch self {
        case .contextOverflow: "Context overflow"
        case .quotaOrRateLimit: "Quota or rate limit"
        case .structuredFailure: "Structured provider failure"
        case .nestedNonZeroExit: "Nested non-zero exit"
        case .unknown: "Unclassified failure"
        }
    }
}

/// Per-provider continuation rules. All fields are intentionally explicit
/// rather than inferred from capability flags so a policy decision is easy
/// to audit in the approval sheet and in tests.
struct ProviderContinuationPolicy: Sendable, Hashable {
    let providerID: String
    let displayName: String
    /// When `true`, a continuation prompt for an eligible trigger is marked
    /// "ready to launch" — the UI still requires an explicit user tap
    /// before any second run starts; auto-resume here means "no extra
    /// approval gate beyond the standard one", not "run silently".
    let allowsAutomaticResume: Bool
    /// Inclusive cap on the depth of an unattended continuation chain. The
    /// originating run is depth 0; the first continuation is depth 1.
    let maxChainDepth: Int
    /// Triggers that produce a continuation prompt at all. Triggers not in
    /// this set return `.notEligible` without ever calling the planner.
    let eligibleTriggers: Set<ContinuationTriggerCategory>
    /// When `true`, the continuation prompt always reminds the agent to
    /// re-read AgentNotes before acting. Defaults to `true` everywhere
    /// because cross-agent coordination is a core safety contract.
    let mustReReadAgentNotes: Bool
    /// Soft note shown to the user explaining why this provider has the
    /// rules it has. Renders in the approval sheet and the live console.
    let resumeNote: String

    /// Whether a follow-up run is allowed at the given chain depth for the
    /// given trigger. Depth comparison is strict-less-than because depth N
    /// means "this is the Nth resume" and the cap is inclusive.
    func permitsContinuation(at chainDepth: Int, trigger: ContinuationTriggerCategory) -> Bool {
        guard eligibleTriggers.contains(trigger) else { return false }
        return chainDepth < maxChainDepth
    }
}

extension ProviderContinuationPolicy {
    /// Conservative default for any provider the catalog hasn't seen yet.
    /// Approval-gated, two resumes max, context overflow only — this is the
    /// posture that fails closed for unknown CLIs.
    static let unknownProviderFallback = ProviderContinuationPolicy(
        providerID: "unknown",
        displayName: "Unknown provider",
        allowsAutomaticResume: false,
        maxChainDepth: 2,
        eligibleTriggers: [.contextOverflow],
        mustReReadAgentNotes: true,
        resumeNote: "No provider-specific rule registered; continuation is approval-gated and capped at two resumes."
    )

    /// Per-provider rules. Tuned for documented behaviour: Codex and Claude
    /// Code can chain a few resume turns safely; CLI tools with brittle
    /// resume semantics are kept approval-gated; Foundation Models stays
    /// approval-gated because session state lives in the on-device model
    /// and cannot be naively re-fed long transcripts.
    static func defaultPolicy(for providerID: String) -> ProviderContinuationPolicy {
        switch providerID {
        case "openai.codex":
            return ProviderContinuationPolicy(
                providerID: providerID,
                displayName: "OpenAI Codex",
                allowsAutomaticResume: true,
                maxChainDepth: 3,
                eligibleTriggers: [.contextOverflow, .structuredFailure, .nestedNonZeroExit],
                mustReReadAgentNotes: true,
                resumeNote: "Codex accepts a resume prompt on stdin; chain stops at three resumes."
            )
        case "anthropic.claude-code":
            return ProviderContinuationPolicy(
                providerID: providerID,
                displayName: "Claude Code",
                allowsAutomaticResume: true,
                maxChainDepth: 3,
                eligibleTriggers: [.contextOverflow, .structuredFailure],
                mustReReadAgentNotes: true,
                resumeNote: "Claude Code can resume with a compacted prompt; chain stops at three resumes."
            )
        case "google.gemini-cli":
            return ProviderContinuationPolicy(
                providerID: providerID,
                displayName: "Gemini CLI",
                allowsAutomaticResume: false,
                maxChainDepth: 2,
                eligibleTriggers: [.contextOverflow, .structuredFailure],
                mustReReadAgentNotes: true,
                resumeNote: "Gemini CLI continuations stay approval-gated until live resume behaviour is reverified."
            )
        case "github.copilot-cli":
            return ProviderContinuationPolicy(
                providerID: providerID,
                displayName: "GitHub Copilot CLI",
                allowsAutomaticResume: false,
                maxChainDepth: 1,
                eligibleTriggers: [.contextOverflow],
                mustReReadAgentNotes: true,
                resumeNote: "Copilot CLI has no documented stateful resume; only context-overflow continuation is offered, approval-gated."
            )
        case "apple.foundation-models":
            return ProviderContinuationPolicy(
                providerID: providerID,
                displayName: "Apple Foundation Models",
                allowsAutomaticResume: false,
                maxChainDepth: 1,
                eligibleTriggers: [.contextOverflow],
                mustReReadAgentNotes: true,
                resumeNote: "Foundation Models session state is in-process; continuation is approval-gated and limited to one resume."
            )
        case "cursor.agent", "kiro.cli", "qwen.code", "mistral.vibe", "opencode.cli":
            return ProviderContinuationPolicy(
                providerID: providerID,
                displayName: providerID,
                allowsAutomaticResume: false,
                maxChainDepth: 2,
                eligibleTriggers: [.contextOverflow, .structuredFailure],
                mustReReadAgentNotes: true,
                resumeNote: "Continuation is approval-gated for this provider until resume semantics are observed live."
            )
        case "xcodebuildmcp.source":
            return ProviderContinuationPolicy(
                providerID: providerID,
                displayName: "XcodeBuildMCP",
                allowsAutomaticResume: false,
                maxChainDepth: 0,
                eligibleTriggers: [],
                mustReReadAgentNotes: true,
                resumeNote: "XcodeBuildMCP is a tool source rather than a chat agent; no continuation is offered."
            )
        case "deepseek.api":
            return ProviderContinuationPolicy(
                providerID: providerID,
                displayName: "DeepSeek",
                allowsAutomaticResume: false,
                maxChainDepth: 1,
                eligibleTriggers: [.contextOverflow],
                mustReReadAgentNotes: true,
                resumeNote: "DeepSeek runs through a user-supplied custom profile; continuation requires explicit approval each turn."
            )
        default:
            return ProviderContinuationPolicy(
                providerID: providerID,
                displayName: providerID,
                allowsAutomaticResume: false,
                maxChainDepth: 2,
                eligibleTriggers: [.contextOverflow],
                mustReReadAgentNotes: true,
                resumeNote: "No provider-specific rule registered; continuation is approval-gated and capped at two resumes."
            )
        }
    }
}

/// Carried into a fresh `RunPlan` so the dispatcher knows which run it is
/// continuing, how deep the chain already is, and why the parent stopped.
/// Optional/additive on the outcome side so older records keep decoding.
struct RunContinuationContext: Sendable, Hashable, Codable {
    let parentRunID: String
    /// 0 = this is the originating run, 1 = first resume, etc. The
    /// dispatcher increments this before persisting an outcome.
    let parentChainDepth: Int
    let triggerCategory: ContinuationTriggerCategory
}

/// Result of asking the policy whether to prepare a continuation prompt.
enum ContinuationDecision: Sendable, Hashable {
    /// Trigger isn't in the eligible set, or the chain has reached the cap.
    case notEligible(reason: String)
    /// A prompt was prepared. `requiresApproval` is true when the policy
    /// keeps the resume behind a second user tap; false when the chain may
    /// proceed under the originating approval (still inside the run sheet).
    case prepared(plan: RunContinuationPlan, requiresApproval: Bool, policy: ProviderContinuationPolicy)
}
