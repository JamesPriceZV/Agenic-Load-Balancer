//
//  SnapshotArchive.swift
//  Agenic Load-Balancer
//
//  Created by Claude on 5/5/26.
//
//  Phase 3: portable archive for the SwiftData master repository. The archive
//  is a versioned JSON envelope (`SnapshotPayload`) wrapping per-model DTOs
//  that round-trip with the live `@Model` classes. Checksums are computed
//  over the canonical JSON encoding of the body so corrupted or tampered
//  archives can be detected before being applied to a live store.
//

import CryptoKit
import Foundation
import SwiftData

/// Schema/format version stamped into every archive. Bumping this lets future
/// readers refuse archives whose shape they don't understand.
enum SnapshotArchiveSchema {
    static let currentVersion = "1.0"
}

/// Top-level archive envelope.
struct SnapshotPayload: Sendable, Codable, Hashable {
    let version: String
    let createdAt: Date
    let appVersion: String
    let checksum: String
    let body: PayloadBody

    init(
        version: String = SnapshotArchiveSchema.currentVersion,
        createdAt: Date,
        appVersion: String,
        checksum: String,
        body: PayloadBody
    ) {
        self.version = version
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.checksum = checksum
        self.body = body
    }
}

/// Body of the archive — the actual record collections. Checksum is computed
/// over the canonical JSON encoding of *this* type only (not the envelope),
/// so the wrapper's metadata can change without invalidating the data hash.
struct PayloadBody: Sendable, Codable, Hashable {
    var projects: [ProjectDTO]
    var providers: [ProviderProfileDTO]
    var providerSetups: [ProviderSetupDTO]
    var providerCommandProfiles: [ProviderCommandProfileDTO]
    var promptThreads: [PromptThreadDTO]
    var promptMessages: [PromptMessageDTO]
    var usageEntries: [UsageLedgerDTO]
    var routingDecisions: [RoutingDecisionDTO]
    var runOutcomes: [RunOutcomeDTO]
    var runTranscriptSegments: [RunTranscriptSegmentDTO]
    var coordinationEvents: [CoordinationEventDTO]
    var cloudSnapshots: [CloudSnapshotDTO]
    var keychainReferences: [KeychainReferenceDTO]
    var autonomyGoals: [AutonomyGoalDTO]
    var autonomyPlans: [AutonomyPlanDTO]
    var autonomyTasks: [AutonomyTaskDTO]
    var autonomyPolicies: [AutonomyPolicyDTO]
    var machinePeers: [MachinePeerDTO]
    var autonomyOperations: [AutonomyOperationDTO]
    var conflictResolutions: [ConflictResolutionDTO]
    var validationGates: [ValidationGateDTO]
    var auditTrails: [AuditTrailDTO]

    enum CodingKeys: String, CodingKey {
        case projects
        case providers
        case providerSetups
        case providerCommandProfiles
        case promptThreads
        case promptMessages
        case usageEntries
        case routingDecisions
        case runOutcomes
        case runTranscriptSegments
        case coordinationEvents
        case cloudSnapshots
        case keychainReferences
        case autonomyGoals
        case autonomyPlans
        case autonomyTasks
        case autonomyPolicies
        case machinePeers
        case autonomyOperations
        case conflictResolutions
        case validationGates
        case auditTrails
    }

    init(
        projects: [ProjectDTO] = [],
        providers: [ProviderProfileDTO] = [],
        providerSetups: [ProviderSetupDTO] = [],
        providerCommandProfiles: [ProviderCommandProfileDTO] = [],
        promptThreads: [PromptThreadDTO] = [],
        promptMessages: [PromptMessageDTO] = [],
        usageEntries: [UsageLedgerDTO] = [],
        routingDecisions: [RoutingDecisionDTO] = [],
        runOutcomes: [RunOutcomeDTO] = [],
        runTranscriptSegments: [RunTranscriptSegmentDTO] = [],
        coordinationEvents: [CoordinationEventDTO] = [],
        cloudSnapshots: [CloudSnapshotDTO] = [],
        keychainReferences: [KeychainReferenceDTO] = [],
        autonomyGoals: [AutonomyGoalDTO] = [],
        autonomyPlans: [AutonomyPlanDTO] = [],
        autonomyTasks: [AutonomyTaskDTO] = [],
        autonomyPolicies: [AutonomyPolicyDTO] = [],
        machinePeers: [MachinePeerDTO] = [],
        autonomyOperations: [AutonomyOperationDTO] = [],
        conflictResolutions: [ConflictResolutionDTO] = [],
        validationGates: [ValidationGateDTO] = [],
        auditTrails: [AuditTrailDTO] = []
    ) {
        self.projects = projects
        self.providers = providers
        self.providerSetups = providerSetups
        self.providerCommandProfiles = providerCommandProfiles
        self.promptThreads = promptThreads
        self.promptMessages = promptMessages
        self.usageEntries = usageEntries
        self.routingDecisions = routingDecisions
        self.runOutcomes = runOutcomes
        self.runTranscriptSegments = runTranscriptSegments
        self.coordinationEvents = coordinationEvents
        self.cloudSnapshots = cloudSnapshots
        self.keychainReferences = keychainReferences
        self.autonomyGoals = autonomyGoals
        self.autonomyPlans = autonomyPlans
        self.autonomyTasks = autonomyTasks
        self.autonomyPolicies = autonomyPolicies
        self.machinePeers = machinePeers
        self.autonomyOperations = autonomyOperations
        self.conflictResolutions = conflictResolutions
        self.validationGates = validationGates
        self.auditTrails = auditTrails
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decodeIfPresent([ProjectDTO].self, forKey: .projects) ?? []
        providers = try container.decodeIfPresent([ProviderProfileDTO].self, forKey: .providers) ?? []
        providerSetups = try container.decodeIfPresent([ProviderSetupDTO].self, forKey: .providerSetups) ?? []
        providerCommandProfiles = try container.decodeIfPresent([ProviderCommandProfileDTO].self, forKey: .providerCommandProfiles) ?? []
        promptThreads = try container.decodeIfPresent([PromptThreadDTO].self, forKey: .promptThreads) ?? []
        promptMessages = try container.decodeIfPresent([PromptMessageDTO].self, forKey: .promptMessages) ?? []
        usageEntries = try container.decodeIfPresent([UsageLedgerDTO].self, forKey: .usageEntries) ?? []
        routingDecisions = try container.decodeIfPresent([RoutingDecisionDTO].self, forKey: .routingDecisions) ?? []
        runOutcomes = try container.decodeIfPresent([RunOutcomeDTO].self, forKey: .runOutcomes) ?? []
        runTranscriptSegments = try container.decodeIfPresent([RunTranscriptSegmentDTO].self, forKey: .runTranscriptSegments) ?? []
        coordinationEvents = try container.decodeIfPresent([CoordinationEventDTO].self, forKey: .coordinationEvents) ?? []
        cloudSnapshots = try container.decodeIfPresent([CloudSnapshotDTO].self, forKey: .cloudSnapshots) ?? []
        keychainReferences = try container.decodeIfPresent([KeychainReferenceDTO].self, forKey: .keychainReferences) ?? []
        autonomyGoals = try container.decodeIfPresent([AutonomyGoalDTO].self, forKey: .autonomyGoals) ?? []
        autonomyPlans = try container.decodeIfPresent([AutonomyPlanDTO].self, forKey: .autonomyPlans) ?? []
        autonomyTasks = try container.decodeIfPresent([AutonomyTaskDTO].self, forKey: .autonomyTasks) ?? []
        autonomyPolicies = try container.decodeIfPresent([AutonomyPolicyDTO].self, forKey: .autonomyPolicies) ?? []
        machinePeers = try container.decodeIfPresent([MachinePeerDTO].self, forKey: .machinePeers) ?? []
        autonomyOperations = try container.decodeIfPresent([AutonomyOperationDTO].self, forKey: .autonomyOperations) ?? []
        conflictResolutions = try container.decodeIfPresent([ConflictResolutionDTO].self, forKey: .conflictResolutions) ?? []
        validationGates = try container.decodeIfPresent([ValidationGateDTO].self, forKey: .validationGates) ?? []
        auditTrails = try container.decodeIfPresent([AuditTrailDTO].self, forKey: .auditTrails) ?? []
    }

    /// Total record count across all model collections.
    var totalRecords: Int {
        countsByModel.values.reduce(0, +)
    }

    /// Per-model counts keyed by stable model identifiers (matches the
    /// "AgentProject", "AgentProviderProfile", etc. names used elsewhere).
    var countsByModel: [String: Int] {
        [
            ModelKey.project: projects.count,
            ModelKey.providerProfile: providers.count,
            ModelKey.providerSetup: providerSetups.count,
            ModelKey.providerCommandProfile: providerCommandProfiles.count,
            ModelKey.promptThread: promptThreads.count,
            ModelKey.promptMessage: promptMessages.count,
            ModelKey.usageLedger: usageEntries.count,
            ModelKey.routingDecision: routingDecisions.count,
            ModelKey.runOutcome: runOutcomes.count,
            ModelKey.runTranscriptSegment: runTranscriptSegments.count,
            ModelKey.coordination: coordinationEvents.count,
            ModelKey.cloudSnapshot: cloudSnapshots.count,
            ModelKey.keychainReference: keychainReferences.count,
            ModelKey.autonomyGoal: autonomyGoals.count,
            ModelKey.autonomyPlan: autonomyPlans.count,
            ModelKey.autonomyTask: autonomyTasks.count,
            ModelKey.autonomyPolicy: autonomyPolicies.count,
            ModelKey.machinePeer: machinePeers.count,
            ModelKey.autonomyOperation: autonomyOperations.count,
            ModelKey.conflictResolution: conflictResolutions.count,
            ModelKey.validationGate: validationGates.count,
            ModelKey.auditTrail: auditTrails.count,
        ]
    }

    /// All identifiers grouped by model key. Used by the diff machinery to
    /// detect overlap between archive and live records.
    var identifiersByModel: [String: Set<String>] {
        [
            ModelKey.project: Set(projects.map(\.identifier)),
            ModelKey.providerProfile: Set(providers.map(\.identifier)),
            ModelKey.providerSetup: Set(providerSetups.map(\.identifier)),
            ModelKey.providerCommandProfile: Set(providerCommandProfiles.map(\.identifier)),
            ModelKey.promptThread: Set(promptThreads.map(\.identifier)),
            ModelKey.promptMessage: Set(promptMessages.map(\.identifier)),
            ModelKey.usageLedger: Set(usageEntries.map(\.identifier)),
            ModelKey.routingDecision: Set(routingDecisions.map(\.identifier)),
            ModelKey.runOutcome: Set(runOutcomes.map(\.identifier)),
            ModelKey.runTranscriptSegment: Set(runTranscriptSegments.map(\.identifier)),
            ModelKey.coordination: Set(coordinationEvents.map(\.identifier)),
            ModelKey.cloudSnapshot: Set(cloudSnapshots.map(\.identifier)),
            ModelKey.keychainReference: Set(keychainReferences.map(\.identifier)),
            ModelKey.autonomyGoal: Set(autonomyGoals.map(\.identifier)),
            ModelKey.autonomyPlan: Set(autonomyPlans.map(\.identifier)),
            ModelKey.autonomyTask: Set(autonomyTasks.map(\.identifier)),
            ModelKey.autonomyPolicy: Set(autonomyPolicies.map(\.identifier)),
            ModelKey.machinePeer: Set(machinePeers.map(\.identifier)),
            ModelKey.autonomyOperation: Set(autonomyOperations.map(\.identifier)),
            ModelKey.conflictResolution: Set(conflictResolutions.map(\.identifier)),
            ModelKey.validationGate: Set(validationGates.map(\.identifier)),
            ModelKey.auditTrail: Set(auditTrails.map(\.identifier)),
        ]
    }
}

/// Stable, human-readable model keys used for cross-model bookkeeping (diffs,
/// counts, UI labels). Keep in sync with the order of `AgenicDataModel.models`.
enum ModelKey {
    static let project = "AgentProject"
    static let promptThread = "PromptThreadRecord"
    static let promptMessage = "PromptMessageRecord"
    static let providerProfile = "AgentProviderProfile"
    static let providerSetup = "ProviderSetupRecord"
    static let providerCommandProfile = "ProviderCommandProfile"
    static let usageLedger = "UsageLedgerEntry"
    static let routingDecision = "RoutingDecisionRecord"
    static let runOutcome = "RunOutcomeRecord"
    static let runTranscriptSegment = "RunTranscriptSegmentRecord"
    static let coordination = "CoordinationEventRecord"
    static let cloudSnapshot = "CloudSnapshotRecord"
    static let keychainReference = "KeychainReferenceRecord"
    static let autonomyGoal = "AutonomyGoalRecord"
    static let autonomyPlan = "AutonomyPlanRecord"
    static let autonomyTask = "AutonomyTaskRecord"
    static let autonomyPolicy = "AutonomyPolicyRecord"
    static let machinePeer = "MachinePeerRecord"
    static let autonomyOperation = "AutonomyOperationRecord"
    static let conflictResolution = "ConflictResolutionRecord"
    static let validationGate = "ValidationGateRecord"
    static let auditTrail = "AuditTrailRecord"

    static let displayLabels: [String: String] = [
        project: "Projects",
        promptThread: "Prompt threads",
        promptMessage: "Prompt messages",
        providerProfile: "Providers",
        providerSetup: "Provider setups",
        providerCommandProfile: "Provider command profiles",
        usageLedger: "Usage entries",
        routingDecision: "Routing decisions",
        runOutcome: "Run outcomes",
        runTranscriptSegment: "Run transcript segments",
        coordination: "Coordination events",
        cloudSnapshot: "Snapshot metadata",
        keychainReference: "Keychain references",
        autonomyGoal: "Autonomy goals",
        autonomyPlan: "Autonomy plans",
        autonomyTask: "Autonomy tasks",
        autonomyPolicy: "Autonomy policies",
        machinePeer: "Machine peers",
        autonomyOperation: "Autonomy operations",
        conflictResolution: "Conflict resolutions",
        validationGate: "Validation gates",
        auditTrail: "Audit trail",
    ]

    static let renderOrder: [String] = [
        project,
        providerProfile,
        providerSetup,
        providerCommandProfile,
        promptThread,
        promptMessage,
        usageLedger,
        routingDecision,
        runOutcome,
        runTranscriptSegment,
        coordination,
        cloudSnapshot,
        keychainReference,
        autonomyGoal,
        autonomyPlan,
        autonomyTask,
        autonomyPolicy,
        machinePeer,
        autonomyOperation,
        conflictResolution,
        validationGate,
        auditTrail,
    ]
}

// MARK: - Per-model DTOs

struct ProjectDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let name: String
    let rootPath: String?
    let bookmarkData: Data?
    let agentNotesRelativePath: String
    let promptExcerptSyncEnabled: Bool
    let defaultWorkingPath: String?
    let temporaryWorkingPath: String?
    let allowToolCalling: Bool?
    let allowShellTools: Bool?
    let allowNetworkSearch: Bool?
    let allowFilesystemWrites: Bool?
    let contextCompactionEnabled: Bool?
    let contextCompactionThresholdTokens: Int?
    let createdAt: Date
    let updatedAt: Date

    init(from record: AgentProject) {
        identifier = record.identifier
        name = record.name
        rootPath = record.rootPath
        bookmarkData = record.bookmarkData
        agentNotesRelativePath = record.agentNotesRelativePath
        promptExcerptSyncEnabled = record.promptExcerptSyncEnabled
        defaultWorkingPath = record.defaultWorkingPath
        temporaryWorkingPath = record.temporaryWorkingPath
        allowToolCalling = record.allowToolCalling
        allowShellTools = record.allowShellTools
        allowNetworkSearch = record.allowNetworkSearch
        allowFilesystemWrites = record.allowFilesystemWrites
        contextCompactionEnabled = record.contextCompactionEnabled
        contextCompactionThresholdTokens = record.contextCompactionThresholdTokens
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func makeRecord() -> AgentProject {
        AgentProject(
            identifier: identifier,
            name: name,
            rootPath: rootPath,
            bookmarkData: bookmarkData,
            agentNotesRelativePath: agentNotesRelativePath,
            promptExcerptSyncEnabled: promptExcerptSyncEnabled,
            defaultWorkingPath: defaultWorkingPath,
            temporaryWorkingPath: temporaryWorkingPath,
            allowToolCalling: allowToolCalling ?? true,
            allowShellTools: allowShellTools ?? true,
            allowNetworkSearch: allowNetworkSearch ?? false,
            allowFilesystemWrites: allowFilesystemWrites ?? true,
            contextCompactionEnabled: contextCompactionEnabled ?? true,
            contextCompactionThresholdTokens: contextCompactionThresholdTokens ?? 120_000,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct PromptThreadDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let projectID: String?
    let title: String
    let status: String
    let createdAt: Date
    let updatedAt: Date

    init(from record: PromptThreadRecord) {
        identifier = record.identifier
        projectID = record.projectID
        title = record.title
        status = record.status
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func makeRecord() -> PromptThreadRecord {
        PromptThreadRecord(
            identifier: identifier,
            projectID: projectID,
            title: title,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct PromptMessageDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let threadID: String?
    let role: String
    let providerID: String?
    let contentExcerpt: String
    let localTranscriptPath: String?
    let createdAt: Date

    init(from record: PromptMessageRecord) {
        identifier = record.identifier
        threadID = record.threadID
        role = record.role
        providerID = record.providerID
        contentExcerpt = record.contentExcerpt
        localTranscriptPath = record.localTranscriptPath
        createdAt = record.createdAt
    }

    func makeRecord() -> PromptMessageRecord {
        PromptMessageRecord(
            identifier: identifier,
            threadID: threadID,
            role: role,
            providerID: providerID,
            contentExcerpt: contentExcerpt,
            localTranscriptPath: localTranscriptPath,
            createdAt: createdAt
        )
    }
}

struct ProviderProfileDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
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
    let installedState: String
    let authState: String
    let lastDetectedVersion: String?
    let lastHealthCheckAt: Date?
    let isEnabled: Bool
    let createdAt: Date
    let updatedAt: Date

    init(from record: AgentProviderProfile) {
        identifier = record.identifier
        displayName = record.displayName
        providerFamily = record.providerFamily
        homepageURL = record.homepageURL
        sourceURL = record.sourceURL
        binaryName = record.binaryName
        installCommand = record.installCommand
        verificationCommand = record.verificationCommand
        authGuide = record.authGuide
        authMethods = record.authMethods
        capabilities = record.capabilities
        supportedExecutionModes = record.supportedExecutionModes
        modelListSource = record.modelListSource
        costPolicySummary = record.costPolicySummary
        quotaPolicySummary = record.quotaPolicySummary
        safetyNotes = record.safetyNotes
        installedState = record.installedState
        authState = record.authState
        lastDetectedVersion = record.lastDetectedVersion
        lastHealthCheckAt = record.lastHealthCheckAt
        isEnabled = record.isEnabled
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func makeRecord() -> AgentProviderProfile {
        let draft = AgentProviderDraft(
            identifier: identifier,
            displayName: displayName,
            providerFamily: providerFamily,
            homepageURL: homepageURL,
            sourceURL: sourceURL,
            binaryName: binaryName,
            installCommand: installCommand,
            verificationCommand: verificationCommand,
            authGuide: authGuide,
            authMethods: authMethods,
            capabilities: capabilities,
            supportedExecutionModes: supportedExecutionModes,
            modelListSource: modelListSource,
            costPolicySummary: costPolicySummary,
            quotaPolicySummary: quotaPolicySummary,
            safetyNotes: safetyNotes
        )
        let record = AgentProviderProfile(draft: draft)
        record.installedState = installedState
        record.authState = authState
        record.lastDetectedVersion = lastDetectedVersion
        record.lastHealthCheckAt = lastHealthCheckAt
        record.isEnabled = isEnabled
        record.createdAt = createdAt
        record.updatedAt = updatedAt
        return record
    }
}

struct ProviderSetupDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let providerID: String
    let setupStage: String
    let lastAction: String
    let lastError: String?
    let installConfirmed: Bool
    let authConfirmed: Bool
    let updatedAt: Date

    init(from record: ProviderSetupRecord) {
        identifier = record.identifier
        providerID = record.providerID
        setupStage = record.setupStage
        lastAction = record.lastAction
        lastError = record.lastError
        installConfirmed = record.installConfirmed
        authConfirmed = record.authConfirmed
        updatedAt = record.updatedAt
    }

    func makeRecord() -> ProviderSetupRecord {
        ProviderSetupRecord(
            identifier: identifier,
            providerID: providerID,
            setupStage: setupStage,
            lastAction: lastAction,
            lastError: lastError,
            installConfirmed: installConfirmed,
            authConfirmed: authConfirmed,
            updatedAt: updatedAt
        )
    }
}

struct ProviderCommandProfileDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let providerID: String
    let displayName: String
    let executablePathOverride: String?
    let argumentTemplate: String
    let environmentJSON: String
    let isEnabled: Bool
    let notes: String
    let createdAt: Date
    let updatedAt: Date

    init(from record: ProviderCommandProfile) {
        identifier = record.identifier
        providerID = record.providerID
        displayName = record.displayName
        executablePathOverride = record.executablePathOverride
        argumentTemplate = record.argumentTemplate
        environmentJSON = record.environmentJSON
        isEnabled = record.isEnabled
        notes = record.notes
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func makeRecord() -> ProviderCommandProfile {
        ProviderCommandProfile(
            identifier: identifier,
            providerID: providerID,
            displayName: displayName,
            executablePathOverride: executablePathOverride,
            argumentTemplate: argumentTemplate,
            environmentJSON: environmentJSON,
            isEnabled: isEnabled,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct UsageLedgerDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let providerID: String
    let modelName: String?
    let runID: String?
    let promptTokens: Int
    let completionTokens: Int
    let cachedPromptTokens: Int?
    let reasoningTokens: Int?
    let callCount: Int
    let estimatedCostUSD: Double
    let durationSeconds: Double
    let preprocessingSeconds: Double?
    let sessionSeconds: Double
    let limitWindow: String
    let createdAt: Date

    init(from record: UsageLedgerEntry) {
        identifier = record.identifier
        providerID = record.providerID
        modelName = record.modelName
        runID = record.runID
        promptTokens = record.promptTokens
        completionTokens = record.completionTokens
        cachedPromptTokens = record.cachedPromptTokens
        reasoningTokens = record.reasoningTokens
        callCount = record.callCount
        estimatedCostUSD = record.estimatedCostUSD
        durationSeconds = record.durationSeconds
        preprocessingSeconds = record.preprocessingSeconds
        sessionSeconds = record.sessionSeconds
        limitWindow = record.limitWindow
        createdAt = record.createdAt
    }

    func makeRecord() -> UsageLedgerEntry {
        UsageLedgerEntry(
            identifier: identifier,
            providerID: providerID,
            modelName: modelName,
            runID: runID,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            cachedPromptTokens: cachedPromptTokens ?? 0,
            reasoningTokens: reasoningTokens ?? 0,
            callCount: callCount,
            estimatedCostUSD: estimatedCostUSD,
            durationSeconds: durationSeconds,
            preprocessingSeconds: preprocessingSeconds ?? 0,
            sessionSeconds: sessionSeconds,
            limitWindow: limitWindow,
            createdAt: createdAt
        )
    }
}

struct RoutingDecisionDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let promptThreadID: String?
    let selectedProviderID: String
    let selectedMode: String
    let scoreSummary: String
    let estimatedCostUSD: Double
    let limitImpact: String
    let coordinationWarnings: String
    let approvedByUser: Bool
    let createdAt: Date

    init(from record: RoutingDecisionRecord) {
        identifier = record.identifier
        promptThreadID = record.promptThreadID
        selectedProviderID = record.selectedProviderID
        selectedMode = record.selectedMode
        scoreSummary = record.scoreSummary
        estimatedCostUSD = record.estimatedCostUSD
        limitImpact = record.limitImpact
        coordinationWarnings = record.coordinationWarnings
        approvedByUser = record.approvedByUser
        createdAt = record.createdAt
    }

    func makeRecord() -> RoutingDecisionRecord {
        RoutingDecisionRecord(
            identifier: identifier,
            promptThreadID: promptThreadID,
            selectedProviderID: selectedProviderID,
            selectedMode: selectedMode,
            scoreSummary: scoreSummary,
            estimatedCostUSD: estimatedCostUSD,
            limitImpact: limitImpact,
            coordinationWarnings: coordinationWarnings,
            approvedByUser: approvedByUser,
            createdAt: createdAt
        )
    }
}

struct RunOutcomeDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let runID: String
    let providerID: String
    let projectID: String?
    let status: String
    let accuracyRating: String
    let linkedRepairRunID: String?
    let buildResult: String
    let userFeedback: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Double
    let commitSHA: String?
    /// Phase 7.2 additive fields. Optional / defaulted so older archives
    /// (written before Phase 7.2 landed) decode cleanly without migration.
    let aiOneLineDescription: String?
    let aiTestsPassed: Int?
    let aiTestsFailed: Int?
    let aiFilesChangedJSON: String?
    let aiSuggestedAccuracyRating: String?
    let aiSummaryGeneratedAt: Date?
    let contextBudgetSummary: String?
    let continuationSummary: String?
    let continuationPrompt: String?
    let transcriptSegmentCount: Int?
    /// Sprint O.1: continuation chain metadata. All optional/defaulted so
    /// archives written before Sprint O.1 still decode and so peers that
    /// haven't received the Sprint O.1 build keep working on the existing
    /// fields. `containsContinuationChainFields` lets snapshot tests
    /// distinguish "field is genuinely absent" from "field decoded as nil".
    let continuationTriggerCategory: String?
    let continuationChainDepth: Int?
    let continuationParentRunID: String?
    let continuationRequiresApproval: Bool?
    let continuationWorkspaceExcerptCount: Int?
    let continuationPolicyNote: String?

    init(from record: RunOutcomeRecord) {
        identifier = record.identifier
        runID = record.runID
        providerID = record.providerID
        projectID = record.projectID
        status = record.status
        accuracyRating = record.accuracyRating
        linkedRepairRunID = record.linkedRepairRunID
        buildResult = record.buildResult
        userFeedback = record.userFeedback
        startedAt = record.startedAt
        endedAt = record.endedAt
        durationSeconds = record.durationSeconds
        commitSHA = record.commitSHA
        aiOneLineDescription = record.aiOneLineDescription
        aiTestsPassed = record.aiTestsPassed
        aiTestsFailed = record.aiTestsFailed
        aiFilesChangedJSON = record.aiFilesChangedJSON
        aiSuggestedAccuracyRating = record.aiSuggestedAccuracyRating
        aiSummaryGeneratedAt = record.aiSummaryGeneratedAt
        contextBudgetSummary = record.contextBudgetSummary
        continuationSummary = record.continuationSummary
        continuationPrompt = record.continuationPrompt
        transcriptSegmentCount = record.transcriptSegmentCount
        continuationTriggerCategory = record.continuationTriggerCategory
        continuationChainDepth = record.continuationChainDepth
        continuationParentRunID = record.continuationParentRunID
        continuationRequiresApproval = record.continuationRequiresApproval
        continuationWorkspaceExcerptCount = record.continuationWorkspaceExcerptCount
        continuationPolicyNote = record.continuationPolicyNote
    }

    func makeRecord() -> RunOutcomeRecord {
        RunOutcomeRecord(
            identifier: identifier,
            runID: runID,
            providerID: providerID,
            projectID: projectID,
            status: status,
            accuracyRating: accuracyRating,
            linkedRepairRunID: linkedRepairRunID,
            buildResult: buildResult,
            userFeedback: userFeedback,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            commitSHA: commitSHA,
            aiOneLineDescription: aiOneLineDescription,
            aiTestsPassed: aiTestsPassed,
            aiTestsFailed: aiTestsFailed,
            aiFilesChangedJSON: aiFilesChangedJSON ?? "[]",
            aiSuggestedAccuracyRating: aiSuggestedAccuracyRating,
            aiSummaryGeneratedAt: aiSummaryGeneratedAt,
            contextBudgetSummary: contextBudgetSummary,
            continuationSummary: continuationSummary,
            continuationPrompt: continuationPrompt,
            transcriptSegmentCount: transcriptSegmentCount ?? 0,
            continuationTriggerCategory: continuationTriggerCategory,
            continuationChainDepth: continuationChainDepth ?? 0,
            continuationParentRunID: continuationParentRunID,
            continuationRequiresApproval: continuationRequiresApproval ?? true,
            continuationWorkspaceExcerptCount: continuationWorkspaceExcerptCount ?? 0,
            continuationPolicyNote: continuationPolicyNote
        )
    }
}

struct RunTranscriptSegmentDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let runID: String
    let providerID: String
    let projectID: String?
    let segmentIndex: Int
    let kind: String
    let text: String
    let tokenEstimate: Int
    let isCompacted: Bool
    let summary: String
    let createdAt: Date

    init(from record: RunTranscriptSegmentRecord) {
        identifier = record.identifier
        runID = record.runID
        providerID = record.providerID
        projectID = record.projectID
        segmentIndex = record.segmentIndex
        kind = record.kind
        text = record.text
        tokenEstimate = record.tokenEstimate
        isCompacted = record.isCompacted
        summary = record.summary
        createdAt = record.createdAt
    }

    func makeRecord() -> RunTranscriptSegmentRecord {
        RunTranscriptSegmentRecord(
            identifier: identifier,
            runID: runID,
            providerID: providerID,
            projectID: projectID,
            segmentIndex: segmentIndex,
            kind: kind,
            text: text,
            tokenEstimate: tokenEstimate,
            isCompacted: isCompacted,
            summary: summary,
            createdAt: createdAt
        )
    }
}

struct CoordinationEventDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
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

    init(from record: CoordinationEventRecord) {
        identifier = record.identifier
        projectID = record.projectID
        phase = record.phase
        wave = record.wave
        step = record.step
        assignee = record.assignee
        status = record.status
        title = record.title
        detail = record.detail
        relatedRunID = record.relatedRunID
        commitSHA = record.commitSHA
        conflictMarker = record.conflictMarker
        createdAt = record.createdAt
    }

    func makeRecord() -> CoordinationEventRecord {
        CoordinationEventRecord(
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

struct CloudSnapshotDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let version: String
    let scope: String
    let recordCounts: String
    let checksum: String
    let restoreNotes: String
    let status: String
    let createdAt: Date

    init(from record: CloudSnapshotRecord) {
        identifier = record.identifier
        version = record.version
        scope = record.scope
        recordCounts = record.recordCounts
        checksum = record.checksum
        restoreNotes = record.restoreNotes
        status = record.status
        createdAt = record.createdAt
    }

    func makeRecord() -> CloudSnapshotRecord {
        CloudSnapshotRecord(
            identifier: identifier,
            version: version,
            scope: scope,
            recordCounts: recordCounts,
            checksum: checksum,
            restoreNotes: restoreNotes,
            status: status,
            createdAt: createdAt
        )
    }
}

struct KeychainReferenceDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let providerID: String
    let serviceName: String
    let accountName: String
    let purpose: String
    let createdAt: Date
    let updatedAt: Date

    init(from record: KeychainReferenceRecord) {
        identifier = record.identifier
        providerID = record.providerID
        serviceName = record.serviceName
        accountName = record.accountName
        purpose = record.purpose
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func makeRecord() -> KeychainReferenceRecord {
        KeychainReferenceRecord(
            identifier: identifier,
            providerID: providerID,
            serviceName: serviceName,
            accountName: accountName,
            purpose: purpose,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct AutonomyGoalDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let projectID: String?
    let title: String
    let goalDescription: String
    let status: String
    let autonomyLevel: String
    let createdAt: Date
    let updatedAt: Date

    init(from record: AutonomyGoalRecord) {
        identifier = record.identifier
        projectID = record.projectID
        title = record.title
        goalDescription = record.goalDescription
        status = record.status
        autonomyLevel = record.autonomyLevel
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func makeRecord() -> AutonomyGoalRecord {
        AutonomyGoalRecord(
            identifier: identifier,
            projectID: projectID,
            title: title,
            goalDescription: goalDescription,
            status: status,
            autonomyLevel: autonomyLevel,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct AutonomyPlanDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let goalID: String?
    let summary: String
    let taskIDsJSON: String
    let createdAt: Date
    let updatedAt: Date

    init(from record: AutonomyPlanRecord) {
        identifier = record.identifier
        goalID = record.goalID
        summary = record.summary
        taskIDsJSON = record.taskIDsJSON
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func makeRecord() -> AutonomyPlanRecord {
        AutonomyPlanRecord(
            identifier: identifier,
            goalID: goalID,
            summary: summary,
            taskIDsJSON: taskIDsJSON,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct AutonomyTaskDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let goalID: String?
    let parentTaskID: String?
    let title: String
    let detail: String
    let status: String
    let mode: String
    let assignedProviderID: String?
    let dependencyIDsJSON: String
    let validationCommand: String?
    let createdAt: Date
    let updatedAt: Date

    init(from record: AutonomyTaskRecord) {
        identifier = record.identifier
        goalID = record.goalID
        parentTaskID = record.parentTaskID
        title = record.title
        detail = record.detail
        status = record.status
        mode = record.mode
        assignedProviderID = record.assignedProviderID
        dependencyIDsJSON = record.dependencyIDsJSON
        validationCommand = record.validationCommand
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func makeRecord() -> AutonomyTaskRecord {
        AutonomyTaskRecord(
            identifier: identifier,
            goalID: goalID,
            parentTaskID: parentTaskID,
            title: title,
            detail: detail,
            status: status,
            mode: mode,
            assignedProviderID: assignedProviderID,
            dependencyIDsJSON: dependencyIDsJSON,
            validationCommand: validationCommand,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct AutonomyPolicyDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let projectID: String?
    let policyJSON: String
    let createdAt: Date
    let updatedAt: Date

    init(from record: AutonomyPolicyRecord) {
        identifier = record.identifier
        projectID = record.projectID
        policyJSON = record.policyJSON
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func makeRecord() -> AutonomyPolicyRecord {
        AutonomyPolicyRecord(
            identifier: identifier,
            projectID: projectID,
            policyJSON: policyJSON,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct MachinePeerDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let displayName: String
    let deviceFingerprintHash: String
    let lastSeenAt: Date?
    let syncStatus: String
    let createdAt: Date
    let updatedAt: Date

    init(from record: MachinePeerRecord) {
        identifier = record.identifier
        displayName = record.displayName
        deviceFingerprintHash = record.deviceFingerprintHash
        lastSeenAt = record.lastSeenAt
        syncStatus = record.syncStatus
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func makeRecord() -> MachinePeerRecord {
        MachinePeerRecord(
            identifier: identifier,
            displayName: displayName,
            deviceFingerprintHash: deviceFingerprintHash,
            lastSeenAt: lastSeenAt,
            syncStatus: syncStatus,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct AutonomyOperationDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let entityID: String
    let entityType: String
    let operationKind: String
    let lamportClock: Int
    let machineID: String
    let payloadJSON: String
    let createdAt: Date

    init(from record: AutonomyOperationRecord) {
        identifier = record.identifier
        entityID = record.entityID
        entityType = record.entityType
        operationKind = record.operationKind
        lamportClock = record.lamportClock
        machineID = record.machineID
        payloadJSON = record.payloadJSON
        createdAt = record.createdAt
    }

    func makeRecord() -> AutonomyOperationRecord {
        AutonomyOperationRecord(
            identifier: identifier,
            entityID: entityID,
            entityType: entityType,
            operationKind: operationKind,
            lamportClock: lamportClock,
            machineID: machineID,
            payloadJSON: payloadJSON,
            createdAt: createdAt
        )
    }
}

struct ConflictResolutionDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let entityID: String
    let conflictKind: String
    let status: String
    let localPayloadJSON: String
    let remotePayloadJSON: String
    let resolutionJSON: String
    let createdAt: Date
    let resolvedAt: Date?

    init(from record: ConflictResolutionRecord) {
        identifier = record.identifier
        entityID = record.entityID
        conflictKind = record.conflictKind
        status = record.status
        localPayloadJSON = record.localPayloadJSON
        remotePayloadJSON = record.remotePayloadJSON
        resolutionJSON = record.resolutionJSON
        createdAt = record.createdAt
        resolvedAt = record.resolvedAt
    }

    func makeRecord() -> ConflictResolutionRecord {
        ConflictResolutionRecord(
            identifier: identifier,
            entityID: entityID,
            conflictKind: conflictKind,
            status: status,
            localPayloadJSON: localPayloadJSON,
            remotePayloadJSON: remotePayloadJSON,
            resolutionJSON: resolutionJSON,
            createdAt: createdAt,
            resolvedAt: resolvedAt
        )
    }
}

struct ValidationGateDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let taskID: String?
    let command: String
    let status: String
    let outputExcerpt: String
    let startedAt: Date?
    let endedAt: Date?

    init(from record: ValidationGateRecord) {
        identifier = record.identifier
        taskID = record.taskID
        command = record.command
        status = record.status
        outputExcerpt = record.outputExcerpt
        startedAt = record.startedAt
        endedAt = record.endedAt
    }

    func makeRecord() -> ValidationGateRecord {
        ValidationGateRecord(
            identifier: identifier,
            taskID: taskID,
            command: command,
            status: status,
            outputExcerpt: outputExcerpt,
            startedAt: startedAt,
            endedAt: endedAt
        )
    }
}

struct AuditTrailDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let goalID: String?
    let taskID: String?
    let eventKind: String
    let detail: String
    let createdAt: Date

    init(from record: AuditTrailRecord) {
        identifier = record.identifier
        goalID = record.goalID
        taskID = record.taskID
        eventKind = record.eventKind
        detail = record.detail
        createdAt = record.createdAt
    }

    func makeRecord() -> AuditTrailRecord {
        AuditTrailRecord(
            identifier: identifier,
            goalID: goalID,
            taskID: taskID,
            eventKind: eventKind,
            detail: detail,
            createdAt: createdAt
        )
    }
}

// MARK: - Coding helpers

/// Errors thrown while reading/writing snapshot archives.
enum SnapshotArchiveError: Error, Sendable, LocalizedError, Equatable {
    case unsupportedVersion(String)
    case checksumMismatch(expected: String, actual: String)
    case decodeFailure(String)
    case encodeFailure(String)
    case fileWriteFailed(String)
    case fileReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v): return "Snapshot archive version \(v) is not supported by this app build."
        case .checksumMismatch(let expected, let actual): return "Snapshot checksum mismatch (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)."
        case .decodeFailure(let msg): return "Could not decode snapshot archive: \(msg)"
        case .encodeFailure(let msg): return "Could not encode snapshot archive: \(msg)"
        case .fileWriteFailed(let msg): return "Could not write snapshot archive: \(msg)"
        case .fileReadFailed(let msg): return "Could not read snapshot archive: \(msg)"
        }
    }
}

/// Stateless helpers for building, encoding, and decoding archives.
enum SnapshotArchiveCodec {
    static var canonicalEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var prettyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Compute a SHA256 hex digest over the canonical JSON encoding of `body`.
    static func checksum(of body: PayloadBody) throws -> String {
        do {
            let data = try canonicalEncoder.encode(body)
            return SHA256.hash(data: data)
                .compactMap { String(format: "%02x", $0) }
                .joined()
        } catch {
            throw SnapshotArchiveError.encodeFailure(error.localizedDescription)
        }
    }

    /// Build a complete payload by computing the checksum over `body`.
    static func makePayload(
        body: PayloadBody,
        appVersion: String,
        createdAt: Date = Date()
    ) throws -> SnapshotPayload {
        let digest = try checksum(of: body)
        return SnapshotPayload(
            createdAt: createdAt,
            appVersion: appVersion,
            checksum: digest,
            body: body
        )
    }

    static func encode(_ payload: SnapshotPayload) throws -> Data {
        do {
            return try prettyEncoder.encode(payload)
        } catch {
            throw SnapshotArchiveError.encodeFailure(error.localizedDescription)
        }
    }

    static func decode(_ data: Data) throws -> SnapshotPayload {
        do {
            return try decoder.decode(SnapshotPayload.self, from: data)
        } catch {
            throw SnapshotArchiveError.decodeFailure(error.localizedDescription)
        }
    }

    /// Verify that a payload's stored checksum matches the canonical hash of
    /// its body, AND that its declared schema version is supported.
    static func verify(_ payload: SnapshotPayload) throws {
        guard payload.version == SnapshotArchiveSchema.currentVersion else {
            throw SnapshotArchiveError.unsupportedVersion(payload.version)
        }
        let actual = try checksum(of: payload.body)
        guard actual == payload.checksum else {
            throw SnapshotArchiveError.checksumMismatch(expected: payload.checksum, actual: actual)
        }
    }
}
