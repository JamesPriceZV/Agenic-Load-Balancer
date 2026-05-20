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
        AutonomyGoalRecord.self,
        AutonomyPlanRecord.self,
        AutonomyTaskRecord.self,
        AutonomyPolicyRecord.self,
        MachinePeerRecord.self,
        AutonomyOperationRecord.self,
        ConflictResolutionRecord.self,
        ValidationGateRecord.self,
        AuditTrailRecord.self,
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

enum AccuracyRating: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
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
    case cancelled
    case checkpointed
    case completed
    case conflict

    var id: String { rawValue }

    static func isActiveForPreflight(_ rawValue: String) -> Bool {
        switch CoordinationStatus(rawValue: rawValue) {
        case .planned, .claimed, .inProgress, .blocked, .conflict:
            return true
        case .cancelled, .checkpointed, .completed, .none:
            return false
        }
    }

    static func isHistorical(_ rawValue: String) -> Bool {
        !isActiveForPreflight(rawValue)
    }
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
    /// Phase 7.2: structured outcome classification produced by Apple
    /// Foundation Models from the captured stdout/stderr buffer of a
    /// successful run. All fields are optional / additive with safe
    /// defaults so existing CloudKit-synced records remain valid.
    var aiOneLineDescription: String?
    var aiTestsPassed: Int?
    var aiTestsFailed: Int?
    /// JSON-encoded `[String]` of files the AI summarizer believes the run
    /// touched. Defaults to `"[]"` so the property is non-optional and
    /// CloudKit-compatible.
    var aiFilesChangedJSON: String = "[]"
    /// `AccuracyRating.rawValue` the AI picked. Distinct from the manual
    /// `accuracyRating` field so user input is never overwritten.
    var aiSuggestedAccuracyRating: String?
    var aiSummaryGeneratedAt: Date?

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
        commitSHA: String? = nil,
        aiOneLineDescription: String? = nil,
        aiTestsPassed: Int? = nil,
        aiTestsFailed: Int? = nil,
        aiFilesChangedJSON: String = "[]",
        aiSuggestedAccuracyRating: String? = nil,
        aiSummaryGeneratedAt: Date? = nil
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
        self.aiOneLineDescription = aiOneLineDescription
        self.aiTestsPassed = aiTestsPassed
        self.aiTestsFailed = aiTestsFailed
        self.aiFilesChangedJSON = aiFilesChangedJSON
        self.aiSuggestedAccuracyRating = aiSuggestedAccuracyRating
        self.aiSummaryGeneratedAt = aiSummaryGeneratedAt
    }
}

extension RunOutcomeRecord {
    /// Phase 7.2: hydrate the AI-summary fields from a `RunSummary`. The
    /// manual `accuracyRating` is intentionally left untouched so the
    /// user's explicit rating wins over the model's suggestion.
    @MainActor
    func applyRunSummary(_ summary: RunSummary, generatedAt: Date = Date()) {
        aiOneLineDescription = summary.oneLineDescription
        aiTestsPassed = summary.testsPassed
        aiTestsFailed = summary.testsFailed
        aiFilesChangedJSON = summary.filesChangedJSON
        aiSuggestedAccuracyRating = summary.suggestedAccuracyRating.rawValue
        aiSummaryGeneratedAt = generatedAt
    }

    /// Decoded view over the JSON-encoded `aiFilesChangedJSON` storage.
    /// Returns `[]` when the field is missing or malformed.
    @MainActor
    var aiFilesChanged: [String] {
        RunSummary.decodeFilesChanged(aiFilesChangedJSON)
    }

    /// Reconstruct a `RunSummary` from the persisted fields, returning
    /// `nil` when the record has not been summarised yet (i.e. no
    /// `aiSummaryGeneratedAt`). Used by the UI to render the AI panel.
    @MainActor
    var aiRunSummary: RunSummary? {
        guard aiSummaryGeneratedAt != nil else { return nil }
        let rating = aiSuggestedAccuracyRating
            .flatMap(AccuracyRating.init(rawValue:)) ?? .unrated
        return RunSummary(
            filesChanged: aiFilesChanged,
            testsPassed: aiTestsPassed,
            testsFailed: aiTestsFailed,
            oneLineDescription: aiOneLineDescription ?? "",
            suggestedAccuracyRating: rating
        )
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

@Model
final class AutonomyGoalRecord {
    var identifier: String = ""
    var projectID: String?
    var title: String = ""
    var goalDescription: String = ""
    var status: String = CoordinationStatus.planned.rawValue
    var autonomyLevel: String = AutonomyLevel.proposeActions.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        projectID: String? = nil,
        title: String,
        goalDescription: String,
        status: String = CoordinationStatus.planned.rawValue,
        autonomyLevel: String = AutonomyLevel.proposeActions.rawValue,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.projectID = projectID
        self.title = title
        self.goalDescription = goalDescription
        self.status = status
        self.autonomyLevel = autonomyLevel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class AutonomyPlanRecord {
    var identifier: String = ""
    var goalID: String?
    var summary: String = ""
    var taskIDsJSON: String = "[]"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        goalID: String? = nil,
        summary: String,
        taskIDsJSON: String = "[]",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.goalID = goalID
        self.summary = summary
        self.taskIDsJSON = taskIDsJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class AutonomyTaskRecord {
    var identifier: String = ""
    var goalID: String?
    var parentTaskID: String?
    var title: String = ""
    var detail: String = ""
    var status: String = CoordinationStatus.planned.rawValue
    var mode: String = AgentExecutionMode.planOnly.rawValue
    var assignedProviderID: String?
    var dependencyIDsJSON: String = "[]"
    var validationCommand: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        goalID: String? = nil,
        parentTaskID: String? = nil,
        title: String,
        detail: String,
        status: String = CoordinationStatus.planned.rawValue,
        mode: String = AgentExecutionMode.planOnly.rawValue,
        assignedProviderID: String? = nil,
        dependencyIDsJSON: String = "[]",
        validationCommand: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.goalID = goalID
        self.parentTaskID = parentTaskID
        self.title = title
        self.detail = detail
        self.status = status
        self.mode = mode
        self.assignedProviderID = assignedProviderID
        self.dependencyIDsJSON = dependencyIDsJSON
        self.validationCommand = validationCommand
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class AutonomyPolicyRecord {
    var identifier: String = ""
    var projectID: String?
    var policyJSON: String = "{}"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        projectID: String? = nil,
        policyJSON: String = "{}",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.projectID = projectID
        self.policyJSON = policyJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class MachinePeerRecord {
    var identifier: String = ""
    var displayName: String = ""
    var deviceFingerprintHash: String = ""
    var lastSeenAt: Date?
    var syncStatus: String = MachineSyncStatus.needsSnapshotVerification.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        displayName: String,
        deviceFingerprintHash: String,
        lastSeenAt: Date? = nil,
        syncStatus: String = MachineSyncStatus.needsSnapshotVerification.rawValue,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.deviceFingerprintHash = deviceFingerprintHash
        self.lastSeenAt = lastSeenAt
        self.syncStatus = syncStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class AutonomyOperationRecord {
    var identifier: String = ""
    var entityID: String = ""
    var entityType: String = ""
    var operationKind: String = ""
    var lamportClock: Int = 0
    var machineID: String = ""
    var payloadJSON: String = "{}"
    var createdAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        entityID: String,
        entityType: String,
        operationKind: String,
        lamportClock: Int = 0,
        machineID: String,
        payloadJSON: String = "{}",
        createdAt: Date = Date()
    ) {
        self.identifier = identifier
        self.entityID = entityID
        self.entityType = entityType
        self.operationKind = operationKind
        self.lamportClock = lamportClock
        self.machineID = machineID
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

@Model
final class ConflictResolutionRecord {
    var identifier: String = ""
    var entityID: String = ""
    var conflictKind: String = ""
    var status: String = "open"
    var localPayloadJSON: String = "{}"
    var remotePayloadJSON: String = "{}"
    var resolutionJSON: String = "{}"
    var createdAt: Date = Date()
    var resolvedAt: Date?

    init(
        identifier: String = UUID().uuidString,
        entityID: String,
        conflictKind: String,
        status: String = "open",
        localPayloadJSON: String = "{}",
        remotePayloadJSON: String = "{}",
        resolutionJSON: String = "{}",
        createdAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.identifier = identifier
        self.entityID = entityID
        self.conflictKind = conflictKind
        self.status = status
        self.localPayloadJSON = localPayloadJSON
        self.remotePayloadJSON = remotePayloadJSON
        self.resolutionJSON = resolutionJSON
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

@Model
final class ValidationGateRecord {
    var identifier: String = ""
    var taskID: String?
    var command: String = ""
    var status: String = "notRun"
    var outputExcerpt: String = ""
    var startedAt: Date?
    var endedAt: Date?

    init(
        identifier: String = UUID().uuidString,
        taskID: String? = nil,
        command: String,
        status: String = "notRun",
        outputExcerpt: String = "",
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.identifier = identifier
        self.taskID = taskID
        self.command = command
        self.status = status
        self.outputExcerpt = outputExcerpt
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

@Model
final class AuditTrailRecord {
    var identifier: String = ""
    var goalID: String?
    var taskID: String?
    var eventKind: String = ""
    var detail: String = ""
    var createdAt: Date = Date()

    init(
        identifier: String = UUID().uuidString,
        goalID: String? = nil,
        taskID: String? = nil,
        eventKind: String,
        detail: String,
        createdAt: Date = Date()
    ) {
        self.identifier = identifier
        self.goalID = goalID
        self.taskID = taskID
        self.eventKind = eventKind
        self.detail = detail
        self.createdAt = createdAt
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
    var isConfiguredForDashboard: Bool {
        guard isEnabled else { return false }
        let availability = ProviderAvailabilityState(rawValue: installedState) ?? .unknown
        let auth = ProviderAuthState(rawValue: authState) ?? .unknown
        if availability == .available { return true }
        if auth == .authenticated || auth == .custom { return true }
        if let lastHealthCheckAt, availability != .missing, availability != .disabled, availability != .error {
            return Date().timeIntervalSince(lastHealthCheckAt) < 60 * 60 * 24 * 30
        }
        return false
    }

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
