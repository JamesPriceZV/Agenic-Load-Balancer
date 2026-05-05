//
//  AgenicModels.swift
//  Agenic Load-Balancer
//
//  Created by OpenAI Codex on 5/5/26.
//

import Foundation
import SwiftData

enum AgenicDataModel {
    static let cloudKitContainerIdentifier = "iCloud.com.zincoverde.Agenic-Load-Balancer"

    static let models: [any PersistentModel.Type] = [
        AgentProject.self,
        PromptThreadRecord.self,
        PromptMessageRecord.self,
        AgentProviderProfile.self,
        ProviderSetupRecord.self,
        ProviderCommandProfile.self,
        UsageLedgerEntry.self,
        RoutingDecisionRecord.self,
        RunOutcomeRecord.self,
        CoordinationEventRecord.self,
        CloudSnapshotRecord.self,
        KeychainReferenceRecord.self,
    ]

    static var schema: Schema {
        Schema(models)
    }
}

enum AgentExecutionMode: String, CaseIterable, Identifiable, Sendable {
    case recommendOnly
    case readReview
    case planOnly
    case implementation
    case repairDebug
    case testBuild
    case commitPushCheckpoint

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommendOnly: "Recommend"
        case .readReview: "Read / Review"
        case .planOnly: "Plan"
        case .implementation: "Implement"
        case .repairDebug: "Repair / Debug"
        case .testBuild: "Test / Build"
        case .commitPushCheckpoint: "Commit / Push"
        }
    }
}

enum ProviderAvailabilityState: String, CaseIterable, Identifiable, Sendable {
    case unknown
    case available
    case missing
    case disabled
    case error

    var id: String { rawValue }
}

enum ProviderAuthState: String, CaseIterable, Identifiable, Sendable {
    case unknown
    case unauthenticated
    case authenticated
    case needsToken
    case browserLoginRequired
    case custom

    var id: String { rawValue }
}

enum RunStatus: String, CaseIterable, Identifiable, Sendable {
    case proposed
    case approved
    case running
    case succeeded
    case failed
    case cancelled

    var id: String { rawValue }
}

enum AccuracyRating: String, CaseIterable, Identifiable, Sendable {
    case unrated
    case correct
    case minorFixNeeded
    case debugNeeded
    case recodeNeeded
    case brokeBuildOrTests
    case abandoned
    case userOverride

    var id: String { rawValue }

    var scoreContribution: Double {
        switch self {
        case .correct: 1.0
        case .minorFixNeeded: 0.72
        case .debugNeeded: 0.48
        case .recodeNeeded: 0.18
        case .brokeBuildOrTests: 0.08
        case .abandoned: 0.0
        case .userOverride: 0.5
        case .unrated: 0.6
        }
    }
}

enum CoordinationStatus: String, CaseIterable, Identifiable, Sendable {
    case planned
    case claimed
    case inProgress
    case blocked
    case checkpointed
    case completed
    case conflict

    var id: String { rawValue }
}

@Model
final class AgentProject {
    var identifier: String = ""
    var name: String = ""
    var rootPath: String?
    var bookmarkData: Data?
    var agentNotesRelativePath: String = "AgentNotes.md"
    var promptExcerptSyncEnabled: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        name: String,
        rootPath: String? = nil,
        bookmarkData: Data? = nil,
        agentNotesRelativePath: String = "AgentNotes.md",
        promptExcerptSyncEnabled: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.name = name
        self.rootPath = rootPath
        self.bookmarkData = bookmarkData
        self.agentNotesRelativePath = agentNotesRelativePath
        self.promptExcerptSyncEnabled = promptExcerptSyncEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PromptThreadRecord {
    var identifier: String = ""
    var projectID: String?
    var title: String = ""
    var status: String = "open"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        projectID: String? = nil,
        title: String,
        status: String = "open",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.projectID = projectID
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PromptMessageRecord {
    var identifier: String = ""
    var threadID: String?
    var role: String = ""
    var providerID: String?
    var contentExcerpt: String = ""
    var localTranscriptPath: String?
    var createdAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        threadID: String? = nil,
        role: String,
        providerID: String? = nil,
        contentExcerpt: String,
        localTranscriptPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.identifier = identifier
        self.threadID = threadID
        self.role = role
        self.providerID = providerID
        self.contentExcerpt = contentExcerpt
        self.localTranscriptPath = localTranscriptPath
        self.createdAt = createdAt
    }
}

@Model
final class AgentProviderProfile {
    var identifier: String = ""
    var displayName: String = ""
    var providerFamily: String = ""
    var homepageURL: String = ""
    var sourceURL: String = ""
    var binaryName: String = ""
    var installCommand: String = ""
    var verificationCommand: String = ""
    var authGuide: String = ""
    var authMethods: String = ""
    var capabilities: String = ""
    var supportedExecutionModes: String = ""
    var modelListSource: String = ""
    var costPolicySummary: String = ""
    var quotaPolicySummary: String = ""
    var safetyNotes: String = ""
    var installedState: String = ProviderAvailabilityState.unknown.rawValue
    var authState: String = ProviderAuthState.unknown.rawValue
    var lastDetectedVersion: String?
    var lastHealthCheckAt: Date?
    var isEnabled: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(draft: AgentProviderDraft) {
        self.identifier = draft.identifier
        self.displayName = draft.displayName
        self.providerFamily = draft.providerFamily
        self.homepageURL = draft.homepageURL
        self.sourceURL = draft.sourceURL
        self.binaryName = draft.binaryName
        self.installCommand = draft.installCommand
        self.verificationCommand = draft.verificationCommand
        self.authGuide = draft.authGuide
        self.authMethods = draft.authMethods
        self.capabilities = draft.capabilities
        self.supportedExecutionModes = draft.supportedExecutionModes
        self.modelListSource = draft.modelListSource
        self.costPolicySummary = draft.costPolicySummary
        self.quotaPolicySummary = draft.quotaPolicySummary
        self.safetyNotes = draft.safetyNotes
        self.installedState = ProviderAvailabilityState.unknown.rawValue
        self.authState = ProviderAuthState.unknown.rawValue
        self.lastDetectedVersion = nil
        self.lastHealthCheckAt = nil
        self.isEnabled = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class ProviderSetupRecord {
    var identifier: String = ""
    var providerID: String = ""
    var setupStage: String = "notStarted"
    var lastAction: String = ""
    var lastError: String?
    var installConfirmed: Bool = false
    var authConfirmed: Bool = false
    var updatedAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        providerID: String,
        setupStage: String = "notStarted",
        lastAction: String = "",
        lastError: String? = nil,
        installConfirmed: Bool = false,
        authConfirmed: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.providerID = providerID
        self.setupStage = setupStage
        self.lastAction = lastAction
        self.lastError = lastError
        self.installConfirmed = installConfirmed
        self.authConfirmed = authConfirmed
        self.updatedAt = updatedAt
    }
}

@Model
final class UsageLedgerEntry {
    var identifier: String = ""
    var providerID: String = ""
    var modelName: String?
    var runID: String?
    var promptTokens: Int = 0
    var completionTokens: Int = 0
    var callCount: Int = 0
    var estimatedCostUSD: Double = 0
    var durationSeconds: Double = 0
    var sessionSeconds: Double = 0
    var limitWindow: String = "manual"
    var createdAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        providerID: String,
        modelName: String? = nil,
        runID: String? = nil,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        callCount: Int = 1,
        estimatedCostUSD: Double = 0,
        durationSeconds: Double = 0,
        sessionSeconds: Double = 0,
        limitWindow: String = "manual",
        createdAt: Date = Date()
    ) {
        self.identifier = identifier
        self.providerID = providerID
        self.modelName = modelName
        self.runID = runID
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.callCount = callCount
        self.estimatedCostUSD = estimatedCostUSD
        self.durationSeconds = durationSeconds
        self.sessionSeconds = sessionSeconds
        self.limitWindow = limitWindow
        self.createdAt = createdAt
    }
}

@Model
final class RoutingDecisionRecord {
    var identifier: String = ""
    var promptThreadID: String?
    var selectedProviderID: String = ""
    var selectedMode: String = ""
    var scoreSummary: String = ""
    var estimatedCostUSD: Double = 0
    var limitImpact: String = "unknown"
    var coordinationWarnings: String = ""
    var approvedByUser: Bool = false
    var createdAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        promptThreadID: String? = nil,
        selectedProviderID: String,
        selectedMode: String,
        scoreSummary: String,
        estimatedCostUSD: Double = 0,
        limitImpact: String = "unknown",
        coordinationWarnings: String = "",
        approvedByUser: Bool = false,
        createdAt: Date = Date()
    ) {
        self.identifier = identifier
        self.promptThreadID = promptThreadID
        self.selectedProviderID = selectedProviderID
        self.selectedMode = selectedMode
        self.scoreSummary = scoreSummary
        self.estimatedCostUSD = estimatedCostUSD
        self.limitImpact = limitImpact
        self.coordinationWarnings = coordinationWarnings
        self.approvedByUser = approvedByUser
        self.createdAt = createdAt
    }
}

@Model
final class RunOutcomeRecord {
    var identifier: String = ""
    var runID: String = ""
    var providerID: String = ""
    var projectID: String?
    var status: String = RunStatus.proposed.rawValue
    var accuracyRating: String = AccuracyRating.unrated.rawValue
    var linkedRepairRunID: String?
    var buildResult: String = "notRun"
    var userFeedback: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    var durationSeconds: Double = 0
    /// Phase 6: commit hash when this run produced a git checkpoint.
    /// Optional + additive, so existing CloudKit-synced records remain valid.
    var commitSHA: String?

    init(
        identifier: String = UUID().uuidString,
        runID: String = UUID().uuidString,
        providerID: String,
        projectID: String? = nil,
        status: String = RunStatus.proposed.rawValue,
        accuracyRating: String = AccuracyRating.unrated.rawValue,
        linkedRepairRunID: String? = nil,
        buildResult: String = "notRun",
        userFeedback: String = "",
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        durationSeconds: Double = 0,
        commitSHA: String? = nil
    ) {
        self.identifier = identifier
        self.runID = runID
        self.providerID = providerID
        self.projectID = projectID
        self.status = status
        self.accuracyRating = accuracyRating
        self.linkedRepairRunID = linkedRepairRunID
        self.buildResult = buildResult
        self.userFeedback = userFeedback
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.commitSHA = commitSHA
    }
}

@Model
final class CoordinationEventRecord {
    var identifier: String = ""
    var projectID: String?
    var phase: String = "Phase 0"
    var wave: String = "Wave 0"
    var step: String = "Step 0"
    var assignee: String = "Agenic Load-Balancer"
    var status: String = CoordinationStatus.planned.rawValue
    var title: String = ""
    var detail: String = ""
    var relatedRunID: String?
    var commitSHA: String?
    var conflictMarker: String?
    var createdAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        projectID: String? = nil,
        phase: String = "Phase 0",
        wave: String = "Wave 0",
        step: String = "Step 0",
        assignee: String = "Agenic Load-Balancer",
        status: String = CoordinationStatus.planned.rawValue,
        title: String,
        detail: String = "",
        relatedRunID: String? = nil,
        commitSHA: String? = nil,
        conflictMarker: String? = nil,
        createdAt: Date = Date()
    ) {
        self.identifier = identifier
        self.projectID = projectID
        self.phase = phase
        self.wave = wave
        self.step = step
        self.assignee = assignee
        self.status = status
        self.title = title
        self.detail = detail
        self.relatedRunID = relatedRunID
        self.commitSHA = commitSHA
        self.conflictMarker = conflictMarker
        self.createdAt = createdAt
    }
}

@Model
final class CloudSnapshotRecord {
    var identifier: String = ""
    var version: String = "1"
    var scope: String = ""
    var recordCounts: String = ""
    var checksum: String = ""
    var restoreNotes: String = ""
    var status: String = "available"
    var createdAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        version: String = "1",
        scope: String,
        recordCounts: String,
        checksum: String,
        restoreNotes: String = "",
        status: String = "available",
        createdAt: Date = Date()
    ) {
        self.identifier = identifier
        self.version = version
        self.scope = scope
        self.recordCounts = recordCounts
        self.checksum = checksum
        self.restoreNotes = restoreNotes
        self.status = status
        self.createdAt = createdAt
    }
}

@Model
final class ProviderCommandProfile {
    /// Stable identifier for the profile record. Defaults to the provider's
    /// own identifier so each provider has at most one profile, but kept as
    /// a regular String (not a unique constraint) for CloudKit compatibility.
    var identifier: String = ""
    var providerID: String = ""
    var displayName: String = ""
    /// Optional override for the executable path. When `nil` the adapter
    /// falls back to PATH-based resolution of the catalog `binaryName`.
    var executablePathOverride: String?
    /// Newline-separated argument template. Each non-empty line is one
    /// argument, with placeholder substitution applied at command-build time:
    /// `{{prompt}}`, `{{project}}`, `{{mode}}`, `{{provider_id}}`.
    var argumentTemplate: String = ""
    /// JSON-encoded `[String: String]` map of environment variables to merge
    /// into the launched process's environment. Stored as a string so the
    /// CloudKit-compatible model rules (no nested complex types) hold.
    var environmentJSON: String = "{}"
    var isEnabled: Bool = false
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        providerID: String,
        displayName: String,
        executablePathOverride: String? = nil,
        argumentTemplate: String = "",
        environmentJSON: String = "{}",
        isEnabled: Bool = false,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.providerID = providerID
        self.displayName = displayName
        self.executablePathOverride = executablePathOverride
        self.argumentTemplate = argumentTemplate
        self.environmentJSON = environmentJSON
        self.isEnabled = isEnabled
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class KeychainReferenceRecord {
    var identifier: String = ""
    var providerID: String = ""
    var serviceName: String = ""
    var accountName: String = ""
    var purpose: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        providerID: String,
        serviceName: String,
        accountName: String,
        purpose: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.providerID = providerID
        self.serviceName = serviceName
        self.accountName = accountName
        self.purpose = purpose
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct AgentProviderDraft: Identifiable, Sendable {
    let identifier: String
    let displayName: String
    let providerFamily: String
    let homepageURL: String
    let sourceURL: String
    let binaryName: String
    let installCommand: String
    let verificationCommand: String
    let authGuide: String
    let authMethods: String
    let capabilities: String
    let supportedExecutionModes: String
    let modelListSource: String
    let costPolicySummary: String
    let quotaPolicySummary: String
    let safetyNotes: String

    var id: String { identifier }
}

struct AgentProviderSnapshot: Identifiable, Sendable {
    let identifier: String
    let displayName: String
    let binaryName: String
    let installCommand: String
    let verificationCommand: String
    let supportedExecutionModes: String
    let capabilities: String
    let installedState: ProviderAvailabilityState
    let authState: ProviderAuthState
    let isEnabled: Bool

    var id: String { identifier }

    func supports(_ mode: AgentExecutionMode) -> Bool {
        supportedExecutionModes
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(mode.rawValue)
    }
}

extension AgentProviderProfile {
    func snapshot() -> AgentProviderSnapshot {
        AgentProviderSnapshot(
            identifier: identifier,
            displayName: displayName,
            binaryName: binaryName,
            installCommand: installCommand,
            verificationCommand: verificationCommand,
            supportedExecutionModes: supportedExecutionModes,
            capabilities: capabilities,
            installedState: ProviderAvailabilityState(rawValue: installedState) ?? .unknown,
            authState: ProviderAuthState(rawValue: authState) ?? .unknown,
            isEnabled: isEnabled
        )
    }
}

struct ProviderCommandProfileSnapshot: Sendable, Hashable, Identifiable {
    let identifier: String
    let providerID: String
    let displayName: String
    let executablePathOverride: String?
    let argumentTemplate: String
    let environmentJSON: String
    let isEnabled: Bool

    var id: String { identifier }

    /// Parsed environment dictionary; returns an empty map if the JSON is
    /// missing or malformed so command construction never throws on bad
    /// user input — the wizard surfaces the parse error separately.
    var environment: [String: String] {
        guard let data = environmentJSON.data(using: .utf8) else { return [:] }
        let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        return decoded ?? [:]
    }

    /// Newline-split argument template trimmed of empty lines. Adapters
    /// substitute placeholders before launching the command.
    var argumentLines: [String] {
        argumentTemplate
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

extension ProviderCommandProfile {
    func snapshot() -> ProviderCommandProfileSnapshot {
        ProviderCommandProfileSnapshot(
            identifier: identifier,
            providerID: providerID,
            displayName: displayName,
            executablePathOverride: executablePathOverride,
            argumentTemplate: argumentTemplate,
            environmentJSON: environmentJSON,
            isEnabled: isEnabled
        )
    }
}

struct ProviderHealthSnapshot: Identifiable, Sendable {
    let providerID: String
    let availabilityState: ProviderAvailabilityState
    let detectedVersion: String?
    let message: String
    let checkedAt: Date

    var id: String { providerID }
}

struct UsageSnapshot: Identifiable, Sendable {
    let providerID: String
    let callsToday: Int
    let tokenCountToday: Int
    let estimatedCostToday: Double
    let sessionSecondsToday: Double
    let limitPressure: Double
    let refreshDate: Date?
    let averageLatencySeconds: Double
    let successRate: Double
    let succeededRunsToday: Int
    let failedRunsToday: Int
    let cancelledRunsToday: Int
    let pressure: UsagePressure?

    var id: String { providerID }

    init(
        providerID: String,
        callsToday: Int,
        tokenCountToday: Int,
        estimatedCostToday: Double,
        sessionSecondsToday: Double,
        limitPressure: Double,
        refreshDate: Date?,
        averageLatencySeconds: Double = 0,
        successRate: Double = 1.0,
        succeededRunsToday: Int = 0,
        failedRunsToday: Int = 0,
        cancelledRunsToday: Int = 0,
        pressure: UsagePressure? = nil
    ) {
        self.providerID = providerID
        self.callsToday = callsToday
        self.tokenCountToday = tokenCountToday
        self.estimatedCostToday = estimatedCostToday
        self.sessionSecondsToday = sessionSecondsToday
        self.limitPressure = limitPressure
        self.refreshDate = refreshDate
        self.averageLatencySeconds = averageLatencySeconds
        self.successRate = successRate
        self.succeededRunsToday = succeededRunsToday
        self.failedRunsToday = failedRunsToday
        self.cancelledRunsToday = cancelledRunsToday
        self.pressure = pressure
    }
}

struct AccuracySnapshot: Identifiable, Sendable {
    let providerID: String
    let totalRatedRuns: Int
    let averageScore: Double
    let correctCount: Int
    let repairCount: Int
    let failureCount: Int

    var id: String { providerID }
}

struct CoordinationEventSnapshot: Identifiable, Sendable {
    let identifier: String
    let projectID: String?
    let phase: String
    let wave: String
    let step: String
    let assignee: String
    let status: String
    let title: String
    let detail: String
    let relatedRunID: String?
    let commitSHA: String?
    let conflictMarker: String?
    let createdAt: Date

    var id: String { identifier }
}

extension CoordinationEventRecord {
    func snapshot() -> CoordinationEventSnapshot {
        CoordinationEventSnapshot(
            identifier: identifier,
            projectID: projectID,
            phase: phase,
            wave: wave,
            step: step,
            assignee: assignee,
            status: status,
            title: title,
            detail: detail,
            relatedRunID: relatedRunID,
            commitSHA: commitSHA,
            conflictMarker: conflictMarker,
            createdAt: createdAt
        )
    }
}
