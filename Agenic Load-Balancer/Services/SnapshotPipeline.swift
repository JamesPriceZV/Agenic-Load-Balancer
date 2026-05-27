//
//  SnapshotPipeline.swift
//  Agenic Load-Balancer
//
//  Created by Claude on 5/5/26.
//
//  Phase 3: MainActor helpers that build a snapshot payload from a live
//  SwiftData context, load a payload into a separate in-memory container for
//  preview, compute a diff between an archive and the live store, and apply
//  the archive either by replacing or merging records. All destructive paths
//  are gated behind explicit caller approval (the UI shows a confirmation
//  dialog before invoking `applyReplace`).
//

import Foundation
import SwiftData

/// Per-model counts and overlap analysis between an archive and the live
/// store. Surfaced to the restore preview UI so users see exactly what would
/// change before approving a replace/merge.
struct SnapshotDiff: Sendable, Hashable {
    let archiveCounts: [String: Int]
    let liveCounts: [String: Int]
    let overlapCounts: [String: Int]
    let archiveOnlyCounts: [String: Int]
    let liveOnlyCounts: [String: Int]

    init(archive: PayloadBody, live: PayloadBody) {
        let archiveCountsLocal = archive.countsByModel
        let liveCountsLocal = live.countsByModel
        let archiveIDs = archive.identifiersByModel
        let liveIDs = live.identifiersByModel

        var overlap: [String: Int] = [:]
        var archiveOnly: [String: Int] = [:]
        var liveOnly: [String: Int] = [:]

        for key in ModelKey.renderOrder {
            let aIDs = archiveIDs[key] ?? []
            let lIDs = liveIDs[key] ?? []
            overlap[key] = aIDs.intersection(lIDs).count
            archiveOnly[key] = aIDs.subtracting(lIDs).count
            liveOnly[key] = lIDs.subtracting(aIDs).count
        }

        self.archiveCounts = archiveCountsLocal
        self.liveCounts = liveCountsLocal
        self.overlapCounts = overlap
        self.archiveOnlyCounts = archiveOnly
        self.liveOnlyCounts = liveOnly
    }

    var totalArchive: Int { archiveCounts.values.reduce(0, +) }
    var totalLive: Int { liveCounts.values.reduce(0, +) }
    var totalOverlap: Int { overlapCounts.values.reduce(0, +) }
    var totalArchiveOnly: Int { archiveOnlyCounts.values.reduce(0, +) }
    var totalLiveOnly: Int { liveOnlyCounts.values.reduce(0, +) }

    func count(for key: String, in counts: [String: Int]) -> Int {
        counts[key] ?? 0
    }
}

/// Summary returned from `applyMerge`. Lets the UI surface "inserted N,
/// skipped M (already present)" without re-walking the payload.
struct SnapshotMergeResult: Sendable, Hashable {
    let inserted: Int
    let skipped: Int
}

/// MainActor-bound helpers that touch SwiftData. The pipeline is
/// intentionally split from the file-I/O side (`SnapshotRestoreCoordinator`
/// actor) so tests can drive it directly with an in-memory `ModelContext`.
@MainActor
enum SnapshotPipeline {
    /// Encode every record in `context` into a checksummed snapshot payload.
    static func buildPayload(
        from context: ModelContext,
        appVersion: String,
        createdAt: Date = Date()
    ) throws -> SnapshotPayload {
        let body = try collectBody(from: context)
        return try SnapshotArchiveCodec.makePayload(
            body: body,
            appVersion: appVersion,
            createdAt: createdAt
        )
    }

    /// Pull every model collection out of `context` and convert to DTOs.
    static func collectBody(from context: ModelContext) throws -> PayloadBody {
        let projects = try context.fetch(FetchDescriptor<AgentProject>())
            .map(ProjectDTO.init(from:))
        let providers = try context.fetch(FetchDescriptor<AgentProviderProfile>())
            .map(ProviderProfileDTO.init(from:))
        let providerSetups = try context.fetch(FetchDescriptor<ProviderSetupRecord>())
            .map(ProviderSetupDTO.init(from:))
        let providerCommandProfiles = try context.fetch(FetchDescriptor<ProviderCommandProfile>())
            .map(ProviderCommandProfileDTO.init(from:))
        let promptThreads = try context.fetch(FetchDescriptor<PromptThreadRecord>())
            .map(PromptThreadDTO.init(from:))
        let promptMessages = try context.fetch(FetchDescriptor<PromptMessageRecord>())
            .map(PromptMessageDTO.init(from:))
        let usageEntries = try context.fetch(FetchDescriptor<UsageLedgerEntry>())
            .map(UsageLedgerDTO.init(from:))
        let routingDecisions = try context.fetch(FetchDescriptor<RoutingDecisionRecord>())
            .map(RoutingDecisionDTO.init(from:))
        let runOutcomes = try context.fetch(FetchDescriptor<RunOutcomeRecord>())
            .map(RunOutcomeDTO.init(from:))
        let runTranscriptSegments = try context.fetch(FetchDescriptor<RunTranscriptSegmentRecord>())
            .map(RunTranscriptSegmentDTO.init(from:))
        let coordinationEvents = try context.fetch(FetchDescriptor<CoordinationEventRecord>())
            .map(CoordinationEventDTO.init(from:))
        let cloudSnapshots = try context.fetch(FetchDescriptor<CloudSnapshotRecord>())
            .map(CloudSnapshotDTO.init(from:))
        let keychainReferences = try context.fetch(FetchDescriptor<KeychainReferenceRecord>())
            .map(KeychainReferenceDTO.init(from:))
        let autonomyGoals = try context.fetch(FetchDescriptor<AutonomyGoalRecord>())
            .map(AutonomyGoalDTO.init(from:))
        let autonomyPlans = try context.fetch(FetchDescriptor<AutonomyPlanRecord>())
            .map(AutonomyPlanDTO.init(from:))
        let autonomyTasks = try context.fetch(FetchDescriptor<AutonomyTaskRecord>())
            .map(AutonomyTaskDTO.init(from:))
        let autonomyPolicies = try context.fetch(FetchDescriptor<AutonomyPolicyRecord>())
            .map(AutonomyPolicyDTO.init(from:))
        let machinePeers = try context.fetch(FetchDescriptor<MachinePeerRecord>())
            .map(MachinePeerDTO.init(from:))
        let autonomyOperations = try context.fetch(FetchDescriptor<AutonomyOperationRecord>())
            .map(AutonomyOperationDTO.init(from:))
        let conflictResolutions = try context.fetch(FetchDescriptor<ConflictResolutionRecord>())
            .map(ConflictResolutionDTO.init(from:))
        let validationGates = try context.fetch(FetchDescriptor<ValidationGateRecord>())
            .map(ValidationGateDTO.init(from:))
        let auditTrails = try context.fetch(FetchDescriptor<AuditTrailRecord>())
            .map(AuditTrailDTO.init(from:))

        return PayloadBody(
            projects: projects,
            providers: providers,
            providerSetups: providerSetups,
            providerCommandProfiles: providerCommandProfiles,
            promptThreads: promptThreads,
            promptMessages: promptMessages,
            usageEntries: usageEntries,
            routingDecisions: routingDecisions,
            runOutcomes: runOutcomes,
            runTranscriptSegments: runTranscriptSegments,
            coordinationEvents: coordinationEvents,
            cloudSnapshots: cloudSnapshots,
            keychainReferences: keychainReferences,
            autonomyGoals: autonomyGoals,
            autonomyPlans: autonomyPlans,
            autonomyTasks: autonomyTasks,
            autonomyPolicies: autonomyPolicies,
            machinePeers: machinePeers,
            autonomyOperations: autonomyOperations,
            conflictResolutions: conflictResolutions,
            validationGates: validationGates,
            auditTrails: auditTrails
        )
    }

    /// Load a payload into a brand new in-memory `ModelContainer` so the
    /// caller can inspect it without touching the live store. Useful for
    /// power-user "open the archive read-only" flows and for tests.
    static func loadPreview(payload: SnapshotPayload) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "AgenicSnapshotPreview-\(UUID().uuidString)",
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: AgenicDataModel.schema,
            configurations: [configuration]
        )
        let previewContext = ModelContext(container)
        insertAll(body: payload.body, into: previewContext)
        try previewContext.save()
        return container
    }

    /// Compute the per-model diff between an archive and the supplied live
    /// `context`. The archive payload is not modified; the live context is
    /// only fetched (read-only).
    static func computeDiff(
        archive: SnapshotPayload,
        against context: ModelContext
    ) throws -> SnapshotDiff {
        let liveBody = try collectBody(from: context)
        return SnapshotDiff(archive: archive.body, live: liveBody)
    }

    /// Destructive: delete every record in `context`, then insert every
    /// record from `payload`. Caller is responsible for confirming with the
    /// user before invoking this. The operation is committed in a single
    /// `save()` so partial failures roll back at the SwiftData layer.
    static func applyReplace(
        payload: SnapshotPayload,
        into context: ModelContext
    ) throws {
        try SnapshotArchiveCodec.verify(payload)
        try deleteAll(in: context)
        insertAll(body: payload.body, into: context)
        try context.save()
    }

    /// Additive: insert every payload record whose identifier is not already
    /// present in `context`. Returns counts so the UI can summarize the
    /// result. Per-model branches are spelled out because each DTO produces
    /// a different concrete `@Model` type and SwiftData's `insert` is generic
    /// over `PersistentModel`.
    static func applyMerge(
        payload: SnapshotPayload,
        into context: ModelContext
    ) throws -> SnapshotMergeResult {
        try SnapshotArchiveCodec.verify(payload)
        let liveIDs = try collectBody(from: context).identifiersByModel
        var inserted = 0
        var skipped = 0

        func mergeProjects() {
            let existing = liveIDs[ModelKey.project] ?? []
            for dto in payload.body.projects {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeProviders() {
            let existing = liveIDs[ModelKey.providerProfile] ?? []
            for dto in payload.body.providers {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeProviderSetups() {
            let existing = liveIDs[ModelKey.providerSetup] ?? []
            for dto in payload.body.providerSetups {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeProviderCommandProfiles() {
            let existing = liveIDs[ModelKey.providerCommandProfile] ?? []
            for dto in payload.body.providerCommandProfiles {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergePromptThreads() {
            let existing = liveIDs[ModelKey.promptThread] ?? []
            for dto in payload.body.promptThreads {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergePromptMessages() {
            let existing = liveIDs[ModelKey.promptMessage] ?? []
            for dto in payload.body.promptMessages {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeUsage() {
            let existing = liveIDs[ModelKey.usageLedger] ?? []
            for dto in payload.body.usageEntries {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeDecisions() {
            let existing = liveIDs[ModelKey.routingDecision] ?? []
            for dto in payload.body.routingDecisions {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeOutcomes() {
            let existing = liveIDs[ModelKey.runOutcome] ?? []
            for dto in payload.body.runOutcomes {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeTranscriptSegments() {
            let existing = liveIDs[ModelKey.runTranscriptSegment] ?? []
            for dto in payload.body.runTranscriptSegments {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeCoordination() {
            let existing = liveIDs[ModelKey.coordination] ?? []
            for dto in payload.body.coordinationEvents {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeCloudSnapshots() {
            let existing = liveIDs[ModelKey.cloudSnapshot] ?? []
            for dto in payload.body.cloudSnapshots {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeKeychainReferences() {
            let existing = liveIDs[ModelKey.keychainReference] ?? []
            for dto in payload.body.keychainReferences {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeAutonomyGoals() {
            let existing = liveIDs[ModelKey.autonomyGoal] ?? []
            for dto in payload.body.autonomyGoals {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeAutonomyPlans() {
            let existing = liveIDs[ModelKey.autonomyPlan] ?? []
            for dto in payload.body.autonomyPlans {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeAutonomyTasks() {
            let existing = liveIDs[ModelKey.autonomyTask] ?? []
            for dto in payload.body.autonomyTasks {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeAutonomyPolicies() {
            let existing = liveIDs[ModelKey.autonomyPolicy] ?? []
            for dto in payload.body.autonomyPolicies {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeMachinePeers() {
            let existing = liveIDs[ModelKey.machinePeer] ?? []
            for dto in payload.body.machinePeers {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeAutonomyOperations() {
            let existing = liveIDs[ModelKey.autonomyOperation] ?? []
            for dto in payload.body.autonomyOperations {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeConflictResolutions() {
            let existing = liveIDs[ModelKey.conflictResolution] ?? []
            for dto in payload.body.conflictResolutions {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeValidationGates() {
            let existing = liveIDs[ModelKey.validationGate] ?? []
            for dto in payload.body.validationGates {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }
        func mergeAuditTrails() {
            let existing = liveIDs[ModelKey.auditTrail] ?? []
            for dto in payload.body.auditTrails {
                if existing.contains(dto.identifier) { skipped += 1 } else {
                    context.insert(dto.makeRecord()); inserted += 1
                }
            }
        }

        mergeProjects()
        mergeProviders()
        mergeProviderSetups()
        mergeProviderCommandProfiles()
        mergePromptThreads()
        mergePromptMessages()
        mergeUsage()
        mergeDecisions()
        mergeOutcomes()
        mergeTranscriptSegments()
        mergeCoordination()
        mergeCloudSnapshots()
        mergeKeychainReferences()
        mergeAutonomyGoals()
        mergeAutonomyPlans()
        mergeAutonomyTasks()
        mergeAutonomyPolicies()
        mergeMachinePeers()
        mergeAutonomyOperations()
        mergeConflictResolutions()
        mergeValidationGates()
        mergeAuditTrails()

        try context.save()
        return SnapshotMergeResult(inserted: inserted, skipped: skipped)
    }

    // MARK: Internal helpers

    private static func insertAll(body: PayloadBody, into context: ModelContext) {
        for dto in body.projects { context.insert(dto.makeRecord()) }
        for dto in body.providers { context.insert(dto.makeRecord()) }
        for dto in body.providerSetups { context.insert(dto.makeRecord()) }
        for dto in body.providerCommandProfiles { context.insert(dto.makeRecord()) }
        for dto in body.promptThreads { context.insert(dto.makeRecord()) }
        for dto in body.promptMessages { context.insert(dto.makeRecord()) }
        for dto in body.usageEntries { context.insert(dto.makeRecord()) }
        for dto in body.routingDecisions { context.insert(dto.makeRecord()) }
        for dto in body.runOutcomes { context.insert(dto.makeRecord()) }
        for dto in body.runTranscriptSegments { context.insert(dto.makeRecord()) }
        for dto in body.coordinationEvents { context.insert(dto.makeRecord()) }
        for dto in body.cloudSnapshots { context.insert(dto.makeRecord()) }
        for dto in body.keychainReferences { context.insert(dto.makeRecord()) }
        for dto in body.autonomyGoals { context.insert(dto.makeRecord()) }
        for dto in body.autonomyPlans { context.insert(dto.makeRecord()) }
        for dto in body.autonomyTasks { context.insert(dto.makeRecord()) }
        for dto in body.autonomyPolicies { context.insert(dto.makeRecord()) }
        for dto in body.machinePeers { context.insert(dto.makeRecord()) }
        for dto in body.autonomyOperations { context.insert(dto.makeRecord()) }
        for dto in body.conflictResolutions { context.insert(dto.makeRecord()) }
        for dto in body.validationGates { context.insert(dto.makeRecord()) }
        for dto in body.auditTrails { context.insert(dto.makeRecord()) }
    }

    private static func deleteAll(in context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<AgentProject>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<AgentProviderProfile>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<ProviderSetupRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<ProviderCommandProfile>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<PromptThreadRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<PromptMessageRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<UsageLedgerEntry>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<RoutingDecisionRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<RunOutcomeRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<RunTranscriptSegmentRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<CoordinationEventRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<CloudSnapshotRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<KeychainReferenceRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<AutonomyGoalRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<AutonomyPlanRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<AutonomyTaskRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<AutonomyPolicyRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<MachinePeerRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<AutonomyOperationRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<ConflictResolutionRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<ValidationGateRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<AuditTrailRecord>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<AutonomousLoopReportRecord>()) { context.delete(record) }
        try context.save()
    }
}
