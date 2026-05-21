//
//  AutonomyReadiness.swift
//  Agenic Load-Balancer
//
//  Readiness scoring for safe autonomous project work.
//

import Foundation

enum AutonomyReadinessState: String, Sendable, Codable, Hashable {
    case ready
    case caution
    case blocked
}

struct AutonomyReadinessCheck: Identifiable, Sendable, Codable, Hashable {
    var id: String { title }
    var title: String
    var detail: String
    var state: AutonomyReadinessState
    var systemImage: String
}

struct AutonomyReadinessSnapshot: Sendable, Codable, Hashable {
    var score: Int
    var state: AutonomyReadinessState
    var title: String
    var detail: String
    var nextAction: String
    var checks: [AutonomyReadinessCheck]
    var activeTaskCount: Int
    var blockedTaskCount: Int
    var completedTaskCount: Int
    var validationGateCount: Int

    var canPrepareAutonomousRuns: Bool {
        !checks.contains { $0.state == .blocked }
    }
}

struct AutonomyReadinessBuilder {
    func build(
        project: AgentProject?,
        providers: [AgentProviderProfile],
        policy: AutonomyPolicy,
        machineHealth: MachineSyncHealth,
        tasks: [AutonomyTaskRecord],
        validationGates: [ValidationGateRecord]
    ) -> AutonomyReadinessSnapshot {
        let checks = [
            workspaceCheck(project),
            providerCheck(providers),
            policyCheck(policy),
            syncCheck(machineHealth),
            taskCheck(tasks),
            validationCheck(tasks: tasks, gates: validationGates),
        ]
        let score = readinessScore(for: checks)
        let state = aggregateState(for: checks)
        return AutonomyReadinessSnapshot(
            score: score,
            state: state,
            title: title(for: state),
            detail: detail(for: state),
            nextAction: nextAction(for: checks),
            checks: checks,
            activeTaskCount: tasks.filter { CoordinationStatus.isActiveForPreflight($0.status) }.count,
            blockedTaskCount: tasks.filter { $0.status == CoordinationStatus.blocked.rawValue || $0.status == CoordinationStatus.conflict.rawValue }.count,
            completedTaskCount: tasks.filter { $0.status == CoordinationStatus.completed.rawValue || $0.status == CoordinationStatus.checkpointed.rawValue }.count,
            validationGateCount: validationGates.count
        )
    }

    private func workspaceCheck(_ project: AgentProject?) -> AutonomyReadinessCheck {
        guard let project else {
            return AutonomyReadinessCheck(
                title: "Workspace",
                detail: "No workspace selected.",
                state: .blocked,
                systemImage: "folder.badge.questionmark"
            )
        }
        let root = project.rootPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if root.isEmpty {
            return AutonomyReadinessCheck(
                title: "Workspace",
                detail: "\(project.name) needs a local root path.",
                state: .blocked,
                systemImage: "folder.badge.minus"
            )
        }
        return AutonomyReadinessCheck(
            title: "Workspace",
            detail: project.name,
            state: .ready,
            systemImage: "folder.badge.gearshape"
        )
    }

    private func providerCheck(_ providers: [AgentProviderProfile]) -> AutonomyReadinessCheck {
        let enabled = providers.filter(\.isEnabled)
        guard !enabled.isEmpty else {
            return AutonomyReadinessCheck(
                title: "Providers",
                detail: "No configured providers are enabled.",
                state: .blocked,
                systemImage: "externaldrive.badge.xmark"
            )
        }
        let ready = enabled.filter {
            $0.installedState == ProviderAvailabilityState.available.rawValue &&
                ($0.authState == ProviderAuthState.authenticated.rawValue || $0.authState == ProviderAuthState.custom.rawValue)
        }
        if ready.isEmpty {
            return AutonomyReadinessCheck(
                title: "Providers",
                detail: "\(enabled.count) enabled, awaiting availability or auth.",
                state: .caution,
                systemImage: "externaldrive.badge.exclamationmark"
            )
        }
        return AutonomyReadinessCheck(
            title: "Providers",
            detail: "\(ready.count) ready of \(enabled.count) enabled.",
            state: .ready,
            systemImage: "externaldrive.connected.to.line.below"
        )
    }

    private func policyCheck(_ policy: AutonomyPolicy) -> AutonomyReadinessCheck {
        if policy.requiresApprovalForShell && policy.requiresApprovalForWrites && policy.requiresApprovalForCommitPush {
            return AutonomyReadinessCheck(
                title: "Approval Gates",
                detail: "\(policy.level.label) with shell, write, and checkpoint approval.",
                state: .ready,
                systemImage: "hand.raised.fill"
            )
        }
        if policy.level == .trustedWorkspaceAutopilot {
            return AutonomyReadinessCheck(
                title: "Approval Gates",
                detail: "Trusted autopilot has relaxed approvals.",
                state: .caution,
                systemImage: "shield.lefthalf.filled.badge.checkmark"
            )
        }
        return AutonomyReadinessCheck(
            title: "Approval Gates",
            detail: "One or more approval gates are relaxed.",
            state: .caution,
            systemImage: "shield.lefthalf.filled"
        )
    }

    private func syncCheck(_ health: MachineSyncHealth) -> AutonomyReadinessCheck {
        switch health.status {
        case .current:
            return AutonomyReadinessCheck(
                title: "Machine Sync",
                detail: health.detail,
                state: .ready,
                systemImage: "icloud"
            )
        case .delayed:
            return AutonomyReadinessCheck(
                title: "Machine Sync",
                detail: health.detail,
                state: .caution,
                systemImage: "icloud.slash"
            )
        case .divergent, .needsSnapshotVerification:
            return AutonomyReadinessCheck(
                title: "Machine Sync",
                detail: health.detail,
                state: .blocked,
                systemImage: "icloud.and.exclamationmark"
            )
        }
    }

    private func taskCheck(_ tasks: [AutonomyTaskRecord]) -> AutonomyReadinessCheck {
        let blocked = tasks.filter { $0.status == CoordinationStatus.blocked.rawValue || $0.status == CoordinationStatus.conflict.rawValue }.count
        if blocked > 0 {
            return AutonomyReadinessCheck(
                title: "Task State",
                detail: "\(blocked) task(s) need review.",
                state: .blocked,
                systemImage: "exclamationmark.triangle.fill"
            )
        }
        let active = tasks.filter { CoordinationStatus.isActiveForPreflight($0.status) }.count
        if active > 0 {
            return AutonomyReadinessCheck(
                title: "Task State",
                detail: "\(active) active task(s) in the queue.",
                state: .ready,
                systemImage: "checklist"
            )
        }
        return AutonomyReadinessCheck(
            title: "Task State",
            detail: "No active autonomous tasks.",
            state: .caution,
            systemImage: "checklist.unchecked"
        )
    }

    private func validationCheck(
        tasks: [AutonomyTaskRecord],
        gates: [ValidationGateRecord]
    ) -> AutonomyReadinessCheck {
        let taskGateCount = tasks.filter { ($0.validationCommand ?? "").isEmpty == false }.count
        if gates.contains(where: { $0.status == "failed" }) {
            return AutonomyReadinessCheck(
                title: "Validation",
                detail: "A validation gate failed.",
                state: .blocked,
                systemImage: "xmark.seal.fill"
            )
        }
        if gates.contains(where: { $0.status == "passed" }) {
            return AutonomyReadinessCheck(
                title: "Validation",
                detail: "\(gates.count) gate record(s), latest pass available.",
                state: .ready,
                systemImage: "checkmark.seal.fill"
            )
        }
        if taskGateCount > 0 {
            return AutonomyReadinessCheck(
                title: "Validation",
                detail: "\(taskGateCount) planned gate(s).",
                state: .ready,
                systemImage: "checkmark.seal"
            )
        }
        return AutonomyReadinessCheck(
            title: "Validation",
            detail: "No validation gate staged yet.",
            state: .caution,
            systemImage: "seal"
        )
    }

    private func readinessScore(for checks: [AutonomyReadinessCheck]) -> Int {
        guard !checks.isEmpty else { return 0 }
        let total = checks.reduce(0) { partial, check in
            partial + score(for: check.state)
        }
        return Int((Double(total) / Double(checks.count)).rounded())
    }

    private func score(for state: AutonomyReadinessState) -> Int {
        switch state {
        case .ready: 100
        case .caution: 65
        case .blocked: 20
        }
    }

    private func aggregateState(for checks: [AutonomyReadinessCheck]) -> AutonomyReadinessState {
        if checks.contains(where: { $0.state == .blocked }) { return .blocked }
        if checks.contains(where: { $0.state == .caution }) { return .caution }
        return .ready
    }

    private func title(for state: AutonomyReadinessState) -> String {
        switch state {
        case .ready: "Ready"
        case .caution: "Guarded"
        case .blocked: "Hold"
        }
    }

    private func detail(for state: AutonomyReadinessState) -> String {
        switch state {
        case .ready: "Autonomy has enough context and guardrails to prepare approval-gated work."
        case .caution: "Autonomy can draft work, but one safety signal needs attention."
        case .blocked: "Autonomy should not proceed until blockers are resolved."
        }
    }

    private func nextAction(for checks: [AutonomyReadinessCheck]) -> String {
        if let blocked = checks.first(where: { $0.state == .blocked }) {
            return "Resolve \(blocked.title.lowercased())."
        }
        if let caution = checks.first(where: { $0.state == .caution }) {
            return "Review \(caution.title.lowercased())."
        }
        return "Draft the next plan."
    }
}
