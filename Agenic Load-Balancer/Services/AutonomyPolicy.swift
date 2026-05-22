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

enum AutonomyTrustLane: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case readOnlyReview
    case planOnly
    case testOnly
    case docsOnlyEdits
    case smallFileEdits
    case dependencyUpdates
    case commitPushCheckpoint

    var id: String { rawValue }

    var label: String {
        switch self {
        case .readOnlyReview: "Read-Only Review"
        case .planOnly: "Plan Only"
        case .testOnly: "Test Only"
        case .docsOnlyEdits: "Docs-Only Edits"
        case .smallFileEdits: "Small File Edits"
        case .dependencyUpdates: "Dependency Updates"
        case .commitPushCheckpoint: "Commit / Push"
        }
    }

    var systemImage: String {
        switch self {
        case .readOnlyReview: "doc.text.magnifyingglass"
        case .planOnly: "list.bullet.rectangle"
        case .testOnly: "checkmark.seal"
        case .docsOnlyEdits: "doc.richtext"
        case .smallFileEdits: "hammer"
        case .dependencyUpdates: "shippingbox.and.arrow.backward"
        case .commitPushCheckpoint: "arrow.up.doc"
        }
    }

    var summary: String {
        switch self {
        case .readOnlyReview:
            "Inspect and summarize the workspace without dispatching mutating work."
        case .planOnly:
            "Create scoped implementation plans and stop before execution."
        case .testOnly:
            "Run bounded validation commands from approved workspace roots."
        case .docsOnlyEdits:
            "Allow small documentation edits after a snapshot or checkpoint exists."
        case .smallFileEdits:
            "Allow bounded source/docs/config edits with validation and rollback evidence."
        case .dependencyUpdates:
            "Allow dependency and lockfile changes only with validation gates and rollback evidence."
        case .commitPushCheckpoint:
            "Allow a validated checkpoint run that can commit and push after explicit approval."
        }
    }

    var allowedModes: [AgentExecutionMode] {
        switch self {
        case .readOnlyReview:
            [.recommendOnly, .readReview]
        case .planOnly:
            [.recommendOnly, .readReview, .planOnly]
        case .testOnly:
            [.recommendOnly, .readReview, .planOnly, .testBuild]
        case .docsOnlyEdits:
            [.recommendOnly, .readReview, .planOnly, .implementation, .testBuild]
        case .smallFileEdits, .dependencyUpdates:
            [.recommendOnly, .readReview, .planOnly, .implementation, .repairDebug, .testBuild]
        case .commitPushCheckpoint:
            AgentExecutionMode.allCases
        }
    }
}

struct AutonomySafetyEvidence: Sendable, Codable, Hashable {
    var hasRecentSnapshot: Bool
    var hasRecentCheckpoint: Bool
    var candidateChangedFileCount: Int
    var command: String?
    var networkRequested: Bool

    init(
        hasRecentSnapshot: Bool = false,
        hasRecentCheckpoint: Bool = false,
        candidateChangedFileCount: Int = 0,
        command: String? = nil,
        networkRequested: Bool = false
    ) {
        self.hasRecentSnapshot = hasRecentSnapshot
        self.hasRecentCheckpoint = hasRecentCheckpoint
        self.candidateChangedFileCount = candidateChangedFileCount
        self.command = command
        self.networkRequested = networkRequested
    }
}

struct AutonomySafetyReview: Sendable, Hashable {
    var lane: AutonomyTrustLane
    var mode: AgentExecutionMode
    var decision: AutonomyPolicyDecision
    var reasons: [String]
    var stopReason: String?

    var isBlocked: Bool {
        if case .denied = decision { return true }
        return false
    }
}

struct AutonomyPolicy: Sendable, Codable, Hashable {
    var level: AutonomyLevel
    var trustLane: AutonomyTrustLane
    var allowedRootPaths: [String]
    var protectedPathPatterns: [String]
    var allowedWritePathPatterns: [String]
    var allowedCommandPrefixes: [String]
    var validationCommands: [String]
    var networkAccessAllowed: Bool
    var requiresApprovalForShell: Bool
    var requiresApprovalForWrites: Bool
    var requiresApprovalForCommitPush: Bool
    var requiresCheckpointBeforeMutation: Bool
    var requiresSnapshotBeforeMutation: Bool
    var maxFilesChangedPerTask: Int
    var maxConcurrentRuns: Int
    var maxEstimatedCostUSD: Double

    init(
        level: AutonomyLevel,
        trustLane: AutonomyTrustLane = .commitPushCheckpoint,
        allowedRootPaths: [String],
        protectedPathPatterns: [String],
        allowedWritePathPatterns: [String] = [],
        allowedCommandPrefixes: [String] = [],
        validationCommands: [String] = [],
        networkAccessAllowed: Bool = false,
        requiresApprovalForShell: Bool,
        requiresApprovalForWrites: Bool,
        requiresApprovalForCommitPush: Bool,
        requiresCheckpointBeforeMutation: Bool = false,
        requiresSnapshotBeforeMutation: Bool = false,
        maxFilesChangedPerTask: Int = 12,
        maxConcurrentRuns: Int,
        maxEstimatedCostUSD: Double
    ) {
        self.level = level
        self.trustLane = trustLane
        self.allowedRootPaths = allowedRootPaths
        self.protectedPathPatterns = protectedPathPatterns
        self.allowedWritePathPatterns = allowedWritePathPatterns
        self.allowedCommandPrefixes = allowedCommandPrefixes
        self.validationCommands = validationCommands
        self.networkAccessAllowed = networkAccessAllowed
        self.requiresApprovalForShell = requiresApprovalForShell
        self.requiresApprovalForWrites = requiresApprovalForWrites
        self.requiresApprovalForCommitPush = requiresApprovalForCommitPush
        self.requiresCheckpointBeforeMutation = requiresCheckpointBeforeMutation
        self.requiresSnapshotBeforeMutation = requiresSnapshotBeforeMutation
        self.maxFilesChangedPerTask = maxFilesChangedPerTask
        self.maxConcurrentRuns = maxConcurrentRuns
        self.maxEstimatedCostUSD = maxEstimatedCostUSD
    }

    static let defaultSafe = AutonomyPolicy(
        level: .proposeActions,
        trustLane: .commitPushCheckpoint,
        allowedRootPaths: [],
        protectedPathPatterns: [".git", ".env", "Secrets", "Keychain", "DerivedData"],
        requiresApprovalForShell: true,
        requiresApprovalForWrites: true,
        requiresApprovalForCommitPush: true,
        maxConcurrentRuns: 2,
        maxEstimatedCostUSD: 1.00
    )

    private enum CodingKeys: String, CodingKey {
        case level
        case trustLane
        case allowedRootPaths
        case protectedPathPatterns
        case allowedWritePathPatterns
        case allowedCommandPrefixes
        case validationCommands
        case networkAccessAllowed
        case requiresApprovalForShell
        case requiresApprovalForWrites
        case requiresApprovalForCommitPush
        case requiresCheckpointBeforeMutation
        case requiresSnapshotBeforeMutation
        case maxFilesChangedPerTask
        case maxConcurrentRuns
        case maxEstimatedCostUSD
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decodeIfPresent(AutonomyLevel.self, forKey: .level) ?? .proposeActions
        trustLane = try container.decodeIfPresent(AutonomyTrustLane.self, forKey: .trustLane) ?? .commitPushCheckpoint
        allowedRootPaths = try container.decodeIfPresent([String].self, forKey: .allowedRootPaths) ?? []
        protectedPathPatterns = try container.decodeIfPresent([String].self, forKey: .protectedPathPatterns) ?? []
        allowedWritePathPatterns = try container.decodeIfPresent([String].self, forKey: .allowedWritePathPatterns) ?? []
        allowedCommandPrefixes = try container.decodeIfPresent([String].self, forKey: .allowedCommandPrefixes) ?? []
        validationCommands = try container.decodeIfPresent([String].self, forKey: .validationCommands) ?? []
        networkAccessAllowed = try container.decodeIfPresent(Bool.self, forKey: .networkAccessAllowed) ?? false
        requiresApprovalForShell = try container.decodeIfPresent(Bool.self, forKey: .requiresApprovalForShell) ?? true
        requiresApprovalForWrites = try container.decodeIfPresent(Bool.self, forKey: .requiresApprovalForWrites) ?? true
        requiresApprovalForCommitPush = try container.decodeIfPresent(Bool.self, forKey: .requiresApprovalForCommitPush) ?? true
        requiresCheckpointBeforeMutation = try container.decodeIfPresent(Bool.self, forKey: .requiresCheckpointBeforeMutation) ?? false
        requiresSnapshotBeforeMutation = try container.decodeIfPresent(Bool.self, forKey: .requiresSnapshotBeforeMutation) ?? false
        maxFilesChangedPerTask = try container.decodeIfPresent(Int.self, forKey: .maxFilesChangedPerTask) ?? 12
        maxConcurrentRuns = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentRuns) ?? 2
        maxEstimatedCostUSD = try container.decodeIfPresent(Double.self, forKey: .maxEstimatedCostUSD) ?? 1.00
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(level, forKey: .level)
        try container.encode(trustLane, forKey: .trustLane)
        try container.encode(allowedRootPaths, forKey: .allowedRootPaths)
        try container.encode(protectedPathPatterns, forKey: .protectedPathPatterns)
        try container.encode(allowedWritePathPatterns, forKey: .allowedWritePathPatterns)
        try container.encode(allowedCommandPrefixes, forKey: .allowedCommandPrefixes)
        try container.encode(validationCommands, forKey: .validationCommands)
        try container.encode(networkAccessAllowed, forKey: .networkAccessAllowed)
        try container.encode(requiresApprovalForShell, forKey: .requiresApprovalForShell)
        try container.encode(requiresApprovalForWrites, forKey: .requiresApprovalForWrites)
        try container.encode(requiresApprovalForCommitPush, forKey: .requiresApprovalForCommitPush)
        try container.encode(requiresCheckpointBeforeMutation, forKey: .requiresCheckpointBeforeMutation)
        try container.encode(requiresSnapshotBeforeMutation, forKey: .requiresSnapshotBeforeMutation)
        try container.encode(maxFilesChangedPerTask, forKey: .maxFilesChangedPerTask)
        try container.encode(maxConcurrentRuns, forKey: .maxConcurrentRuns)
        try container.encode(maxEstimatedCostUSD, forKey: .maxEstimatedCostUSD)
    }
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
        if !policy.allowedWritePathPatterns.isEmpty,
           !policy.allowedWritePathPatterns.contains(where: { matchesPathPattern($0, path: path) }) {
            return .denied("Path is outside the \(policy.trustLane.label) write allowlist.")
        }
        return policy.requiresApprovalForWrites ? .requiresApproval("Writes require approval.") : .allowed
    }

    func evaluateRun(
        mode: AgentExecutionMode,
        estimatedCostUSD: Double,
        policy: AutonomyPolicy,
        evidence: AutonomySafetyEvidence? = nil
    ) -> AutonomyPolicyDecision {
        guard estimatedCostUSD <= policy.maxEstimatedCostUSD else {
            return .denied("Estimated cost exceeds policy budget.")
        }
        guard policy.trustLane.allowedModes.contains(mode) else {
            return .denied("\(policy.trustLane.label) lane does not allow \(mode.label) runs.")
        }
        if policy.level == .observeOnly && mode != .recommendOnly {
            return .denied("Observe-only autonomy cannot dispatch runs.")
        }
        if policy.level == .planOnly && mode != .recommendOnly && mode != .planOnly {
            return .requiresApproval("Plan-only autonomy cannot execute without approval.")
        }
        if let evidence {
            if evidence.candidateChangedFileCount > policy.maxFilesChangedPerTask {
                return .denied("Candidate changes exceed the \(policy.trustLane.label) file limit.")
            }
            if evidence.networkRequested && !policy.networkAccessAllowed {
                return .denied("\(policy.trustLane.label) lane does not allow network access.")
            }
            let commandDecision = evaluateCommand(evidence.command, policy: policy)
            if case .denied = commandDecision {
                return commandDecision
            }
        }
        if mode.isMutatingAutonomyMode && policy.requiresSnapshotBeforeMutation && evidence?.hasRecentSnapshot != true {
            return .denied("Create a successful snapshot before using \(policy.trustLane.label).")
        }
        if mode.isMutatingAutonomyMode && policy.requiresCheckpointBeforeMutation {
            let hasRollbackAnchor = evidence?.hasRecentCheckpoint == true || evidence?.hasRecentSnapshot == true
            if !hasRollbackAnchor {
                return .denied("Create a snapshot or git checkpoint before using \(policy.trustLane.label).")
            }
        }
        if mode == .commitPushCheckpoint && policy.requiresApprovalForCommitPush {
            return .requiresApproval("Commit and push require approval.")
        }
        if policy.requiresApprovalForShell && mode != .recommendOnly && mode != .planOnly {
            return .requiresApproval("Shell-backed execution requires approval.")
        }
        return .allowed
    }

    func evaluateCommand(_ command: String?, policy: AutonomyPolicy) -> AutonomyPolicyDecision {
        let trimmed = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !policy.allowedCommandPrefixes.isEmpty else {
            return .allowed
        }
        let normalized = trimmed.replacingOccurrences(of: "\n", with: " ")
        if policy.allowedCommandPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return .allowed
        }
        return .denied("Command is outside the \(policy.trustLane.label) allowlist.")
    }

    func safetyReview(
        title: String,
        mode: AgentExecutionMode,
        estimatedCostUSD: Double,
        policy: AutonomyPolicy,
        evidence: AutonomySafetyEvidence
    ) -> AutonomySafetyReview {
        let decision = evaluateRun(
            mode: mode,
            estimatedCostUSD: estimatedCostUSD,
            policy: policy,
            evidence: evidence
        )
        let roots = policy.allowedRootPaths.isEmpty ? "no roots" : policy.allowedRootPaths.joined(separator: ", ")
        var reasons = [
            "\(policy.trustLane.label) allows \(policy.trustLane.allowedModes.map(\.label).joined(separator: ", ")).",
            "Allowed roots: \(roots).",
            "Protected paths: \(policy.protectedPathPatterns.joined(separator: ", ")).",
            policy.networkAccessAllowed ? "Network access may be requested inside this lane." : "Network access is disabled for this lane.",
            "Budget cap: \(Self.currency(policy.maxEstimatedCostUSD)); file cap: \(policy.maxFilesChangedPerTask).",
        ]
        if policy.requiresCheckpointBeforeMutation || policy.requiresSnapshotBeforeMutation {
            let evidenceText = [
                evidence.hasRecentSnapshot ? "snapshot ready" : "no snapshot",
                evidence.hasRecentCheckpoint ? "checkpoint ready" : "no checkpoint",
            ].joined(separator: ", ")
            reasons.append("Rollback evidence: \(evidenceText).")
        }
        if !policy.allowedCommandPrefixes.isEmpty {
            reasons.append("\(policy.allowedCommandPrefixes.count) command prefix(es) are allowlisted.")
        }
        let stopReason: String?
        if case .denied(let reason) = decision {
            stopReason = reason
        } else {
            stopReason = nil
        }
        return AutonomySafetyReview(
            lane: policy.trustLane,
            mode: mode,
            decision: decision,
            reasons: reasons,
            stopReason: stopReason
        )
    }

    private func isPath(_ path: String, insideRoot root: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        return normalizedPath == normalizedRoot || normalizedPath.hasPrefix(normalizedRoot + "/")
    }

    private func matchesPathPattern(_ pattern: String, path: String) -> Bool {
        if pattern.hasPrefix("*.") {
            return path.hasSuffix(String(pattern.dropFirst()))
        }
        return path.contains(pattern)
    }

    private static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

struct AutonomyTrustLaneTemplate: Identifiable, Sendable, Hashable {
    var lane: AutonomyTrustLane
    var rootPath: String?
    var level: AutonomyLevel

    var id: AutonomyTrustLane { lane }

    var policy: AutonomyPolicy {
        let rootPaths = rootPath.map { [$0] } ?? []
        switch lane {
        case .readOnlyReview:
            return makePolicy(
                rootPaths: rootPaths,
                protectedPaths: baseProtectedPaths,
                allowedWrites: [],
                commands: readOnlyCommands,
                validation: [],
                networkAllowed: false,
                approvalForShell: true,
                approvalForWrites: true,
                approvalForCommitPush: true,
                checkpointRequired: false,
                snapshotRequired: false,
                maxFiles: 0,
                budget: 0.10
            )
        case .planOnly:
            return makePolicy(
                rootPaths: rootPaths,
                protectedPaths: baseProtectedPaths,
                allowedWrites: [],
                commands: readOnlyCommands,
                validation: [],
                networkAllowed: false,
                approvalForShell: true,
                approvalForWrites: true,
                approvalForCommitPush: true,
                checkpointRequired: false,
                snapshotRequired: false,
                maxFiles: 0,
                budget: 0.25
            )
        case .testOnly:
            return makePolicy(
                rootPaths: rootPaths,
                protectedPaths: baseProtectedPaths,
                allowedWrites: [],
                commands: validationCommands,
                validation: [defaultXcodeTestCommand],
                networkAllowed: false,
                approvalForShell: true,
                approvalForWrites: true,
                approvalForCommitPush: true,
                checkpointRequired: false,
                snapshotRequired: false,
                maxFiles: 0,
                budget: 0.50
            )
        case .docsOnlyEdits:
            return makePolicy(
                rootPaths: rootPaths,
                protectedPaths: baseProtectedPaths + ["Agenic Load-Balancer/Services", "Agenic Load-Balancer/Models"],
                allowedWrites: ["*.md", "*.markdown", "README", "Docs/"],
                commands: readOnlyCommands + validationCommands,
                validation: ["git diff --check"],
                networkAllowed: false,
                approvalForShell: true,
                approvalForWrites: true,
                approvalForCommitPush: true,
                checkpointRequired: true,
                snapshotRequired: false,
                maxFiles: 6,
                budget: 0.50
            )
        case .smallFileEdits:
            return makePolicy(
                rootPaths: rootPaths,
                protectedPaths: baseProtectedPaths,
                allowedWrites: ["*.swift", "*.md", "*.json", "*.plist", "*.yml", "*.yaml"],
                commands: readOnlyCommands + validationCommands,
                validation: [defaultXcodeTestCommand],
                networkAllowed: false,
                approvalForShell: true,
                approvalForWrites: true,
                approvalForCommitPush: true,
                checkpointRequired: true,
                snapshotRequired: false,
                maxFiles: 12,
                budget: 1.00
            )
        case .dependencyUpdates:
            return makePolicy(
                rootPaths: rootPaths,
                protectedPaths: baseProtectedPaths,
                allowedWrites: ["Package.swift", "Package.resolved", "project.pbxproj", "*.xcodeproj"],
                commands: readOnlyCommands + validationCommands + ["swift package", "npm outdated", "npm test"],
                validation: [defaultXcodeTestCommand],
                networkAllowed: true,
                approvalForShell: true,
                approvalForWrites: true,
                approvalForCommitPush: true,
                checkpointRequired: true,
                snapshotRequired: true,
                maxFiles: 8,
                budget: 1.50
            )
        case .commitPushCheckpoint:
            return makePolicy(
                rootPaths: rootPaths,
                protectedPaths: baseProtectedPaths,
                allowedWrites: ["*.swift", "*.md", "*.json", "*.plist", "*.yml", "*.yaml", "project.pbxproj"],
                commands: readOnlyCommands + validationCommands + ["git add", "git commit", "git push"],
                validation: [defaultXcodeTestCommand, "git diff --check"],
                networkAllowed: false,
                approvalForShell: true,
                approvalForWrites: true,
                approvalForCommitPush: true,
                checkpointRequired: true,
                snapshotRequired: false,
                maxFiles: 20,
                budget: 2.00
            )
        }
    }

    private var baseProtectedPaths: [String] {
        [".git", ".env", "Secrets", "Keychain", "DerivedData", ".xcresult"]
    }

    private var readOnlyCommands: [String] {
        ["git status", "git diff", "rg", "sed", "find", "xcodebuild -list"]
    }

    private var validationCommands: [String] {
        [
            "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild",
            "xcodebuild",
            "swift test",
            "swift build",
            "./script/build_and_run.sh --verify",
            "git diff --check",
        ]
    }

    private var defaultXcodeTestCommand: String {
        """
        DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS,arch=arm64" CODE_SIGNING_ALLOWED=NO test
        """
    }

    private func makePolicy(
        rootPaths: [String],
        protectedPaths: [String],
        allowedWrites: [String],
        commands: [String],
        validation: [String],
        networkAllowed: Bool,
        approvalForShell: Bool,
        approvalForWrites: Bool,
        approvalForCommitPush: Bool,
        checkpointRequired: Bool,
        snapshotRequired: Bool,
        maxFiles: Int,
        budget: Double
    ) -> AutonomyPolicy {
        AutonomyPolicy(
            level: level,
            trustLane: lane,
            allowedRootPaths: rootPaths,
            protectedPathPatterns: protectedPaths,
            allowedWritePathPatterns: allowedWrites,
            allowedCommandPrefixes: commands,
            validationCommands: validation,
            networkAccessAllowed: networkAllowed,
            requiresApprovalForShell: approvalForShell,
            requiresApprovalForWrites: approvalForWrites,
            requiresApprovalForCommitPush: approvalForCommitPush,
            requiresCheckpointBeforeMutation: checkpointRequired,
            requiresSnapshotBeforeMutation: snapshotRequired,
            maxFilesChangedPerTask: maxFiles,
            maxConcurrentRuns: 1,
            maxEstimatedCostUSD: budget
        )
    }
}

extension AgentExecutionMode {
    var isMutatingAutonomyMode: Bool {
        switch self {
        case .implementation, .repairDebug, .commitPushCheckpoint:
            true
        case .recommendOnly, .readReview, .planOnly, .testBuild:
            false
        }
    }
}
