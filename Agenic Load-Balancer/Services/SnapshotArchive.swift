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
    var promptThreads: [PromptThreadDTO]
    var promptMessages: [PromptMessageDTO]
    var usageEntries: [UsageLedgerDTO]
    var routingDecisions: [RoutingDecisionDTO]
    var runOutcomes: [RunOutcomeDTO]
    var coordinationEvents: [CoordinationEventDTO]
    var cloudSnapshots: [CloudSnapshotDTO]
    var keychainReferences: [KeychainReferenceDTO]

    init(
        projects: [ProjectDTO] = [],
        providers: [ProviderProfileDTO] = [],
        providerSetups: [ProviderSetupDTO] = [],
        promptThreads: [PromptThreadDTO] = [],
        promptMessages: [PromptMessageDTO] = [],
        usageEntries: [UsageLedgerDTO] = [],
        routingDecisions: [RoutingDecisionDTO] = [],
        runOutcomes: [RunOutcomeDTO] = [],
        coordinationEvents: [CoordinationEventDTO] = [],
        cloudSnapshots: [CloudSnapshotDTO] = [],
        keychainReferences: [KeychainReferenceDTO] = []
    ) {
        self.projects = projects
        self.providers = providers
        self.providerSetups = providerSetups
        self.promptThreads = promptThreads
        self.promptMessages = promptMessages
        self.usageEntries = usageEntries
        self.routingDecisions = routingDecisions
        self.runOutcomes = runOutcomes
        self.coordinationEvents = coordinationEvents
        self.cloudSnapshots = cloudSnapshots
        self.keychainReferences = keychainReferences
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
            ModelKey.promptThread: promptThreads.count,
            ModelKey.promptMessage: promptMessages.count,
            ModelKey.usageLedger: usageEntries.count,
            ModelKey.routingDecision: routingDecisions.count,
            ModelKey.runOutcome: runOutcomes.count,
            ModelKey.coordination: coordinationEvents.count,
            ModelKey.cloudSnapshot: cloudSnapshots.count,
            ModelKey.keychainReference: keychainReferences.count,
        ]
    }

    /// All identifiers grouped by model key. Used by the diff machinery to
    /// detect overlap between archive and live records.
    var identifiersByModel: [String: Set<String>] {
        [
            ModelKey.project: Set(projects.map(\.identifier)),
            ModelKey.providerProfile: Set(providers.map(\.identifier)),
            ModelKey.providerSetup: Set(providerSetups.map(\.identifier)),
            ModelKey.promptThread: Set(promptThreads.map(\.identifier)),
            ModelKey.promptMessage: Set(promptMessages.map(\.identifier)),
            ModelKey.usageLedger: Set(usageEntries.map(\.identifier)),
            ModelKey.routingDecision: Set(routingDecisions.map(\.identifier)),
            ModelKey.runOutcome: Set(runOutcomes.map(\.identifier)),
            ModelKey.coordination: Set(coordinationEvents.map(\.identifier)),
            ModelKey.cloudSnapshot: Set(cloudSnapshots.map(\.identifier)),
            ModelKey.keychainReference: Set(keychainReferences.map(\.identifier)),
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
    static let usageLedger = "UsageLedgerEntry"
    static let routingDecision = "RoutingDecisionRecord"
    static let runOutcome = "RunOutcomeRecord"
    static let coordination = "CoordinationEventRecord"
    static let cloudSnapshot = "CloudSnapshotRecord"
    static let keychainReference = "KeychainReferenceRecord"

    static let displayLabels: [String: String] = [
        project: "Projects",
        promptThread: "Prompt threads",
        promptMessage: "Prompt messages",
        providerProfile: "Providers",
        providerSetup: "Provider setups",
        usageLedger: "Usage entries",
        routingDecision: "Routing decisions",
        runOutcome: "Run outcomes",
        coordination: "Coordination events",
        cloudSnapshot: "Snapshot metadata",
        keychainReference: "Keychain references",
    ]

    static let renderOrder: [String] = [
        project,
        providerProfile,
        providerSetup,
        promptThread,
        promptMessage,
        usageLedger,
        routingDecision,
        runOutcome,
        coordination,
        cloudSnapshot,
        keychainReference,
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
    let createdAt: Date
    let updatedAt: Date

    init(from record: AgentProject) {
        identifier = record.identifier
        name = record.name
        rootPath = record.rootPath
        bookmarkData = record.bookmarkData
        agentNotesRelativePath = record.agentNotesRelativePath
        promptExcerptSyncEnabled = record.promptExcerptSyncEnabled
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

struct UsageLedgerDTO: Sendable, Codable, Hashable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let providerID: String
    let modelName: String?
    let runID: String?
    let promptTokens: Int
    let completionTokens: Int
    let callCount: Int
    let estimatedCostUSD: Double
    let durationSeconds: Double
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
        callCount = record.callCount
        estimatedCostUSD = record.estimatedCostUSD
        durationSeconds = record.durationSeconds
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
            callCount: callCount,
            estimatedCostUSD: estimatedCostUSD,
            durationSeconds: durationSeconds,
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
    // Phase 7.2: optional classification fields — older archives decode these as nil.
    let classifiedFilesChanged: String?
    let classifiedTestsPassed: Int?
    let classifiedTestsFailed: Int?
    let classifiedDescription: String?
    let classifiedAccuracyRating: String?

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
        classifiedFilesChanged = record.classifiedFilesChanged
        classifiedTestsPassed = record.classifiedTestsPassed
        classifiedTestsFailed = record.classifiedTestsFailed
        classifiedDescription = record.classifiedDescription
        classifiedAccuracyRating = record.classifiedAccuracyRating
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
            classifiedFilesChanged: classifiedFilesChanged,
            classifiedTestsPassed: classifiedTestsPassed,
            classifiedTestsFailed: classifiedTestsFailed,
            classifiedDescription: classifiedDescription,
            classifiedAccuracyRating: classifiedAccuracyRating
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
