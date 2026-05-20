//
//  AutonomyPolicy.swift
//  Agenic Load-Balancer
//
//  Phase 7.6: policy gates for autonomous project management.
//

import Foundation

enum AutonomyLevel: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case observeOnly
    case planOnly
    case proposeActions
    case executeApprovedSteps
    case trustedWorkspaceAutopilot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .observeOnly: "Observe Only"
        case .planOnly: "Plan Only"
        case .proposeActions: "Propose Actions"
        case .executeApprovedSteps: "Execute Approved"
        case .trustedWorkspaceAutopilot: "Trusted Autopilot"
        }
    }
}

struct AutonomyPolicy: Sendable, Codable, Hashable {
    var level: AutonomyLevel
    var allowedRootPaths: [String]
    var protectedPathPatterns: [String]
    var requiresApprovalForShell: Bool
    var requiresApprovalForWrites: Bool
    var requiresApprovalForCommitPush: Bool
    var maxConcurrentRuns: Int
    var maxEstimatedCostUSD: Double

    static let defaultSafe = AutonomyPolicy(
        level: .proposeActions,
        allowedRootPaths: [],
        protectedPathPatterns: [".git", ".env", "Secrets", "Keychain", "DerivedData"],
        requiresApprovalForShell: true,
        requiresApprovalForWrites: true,
        requiresApprovalForCommitPush: true,
        maxConcurrentRuns: 2,
        maxEstimatedCostUSD: 1.00
    )
}

enum AutonomyPolicyDecision: Sendable, Equatable, Hashable {
    case allowed
    case requiresApproval(String)
    case denied(String)

    var isAllowedWithoutApproval: Bool {
        if case .allowed = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .allowed:
            return "Allowed."
        case .requiresApproval(let reason), .denied(let reason):
            return reason
        }
    }
}

struct AutonomyPolicyEvaluator: Sendable {
    func evaluateWrite(path: String, policy: AutonomyPolicy) -> AutonomyPolicyDecision {
        guard policy.allowedRootPaths.contains(where: { isPath(path, insideRoot: $0) }) else {
            return .denied("Path is outside allowed project roots.")
        }
        if policy.protectedPathPatterns.contains(where: { path.contains($0) }) {
            return .requiresApproval("Path matches protected pattern.")
        }
        return policy.requiresApprovalForWrites ? .requiresApproval("Writes require approval.") : .allowed
    }

    func evaluateRun(
        mode: AgentExecutionMode,
        estimatedCostUSD: Double,
        policy: AutonomyPolicy
    ) -> AutonomyPolicyDecision {
        guard estimatedCostUSD <= policy.maxEstimatedCostUSD else {
            return .denied("Estimated cost exceeds policy budget.")
        }
        if policy.level == .observeOnly && mode != .recommendOnly {
            return .denied("Observe-only autonomy cannot dispatch runs.")
        }
        if policy.level == .planOnly && mode != .recommendOnly && mode != .planOnly {
            return .requiresApproval("Plan-only autonomy cannot execute without approval.")
        }
        if mode == .commitPushCheckpoint && policy.requiresApprovalForCommitPush {
            return .requiresApproval("Commit and push require approval.")
        }
        if policy.requiresApprovalForShell && mode != .recommendOnly && mode != .planOnly {
            return .requiresApproval("Shell-backed execution requires approval.")
        }
        return .allowed
    }

    private func isPath(_ path: String, insideRoot root: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        return normalizedPath == normalizedRoot || normalizedPath.hasPrefix(normalizedRoot + "/")
    }
}
