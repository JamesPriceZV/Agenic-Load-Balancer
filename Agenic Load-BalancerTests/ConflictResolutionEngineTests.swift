//
//  ConflictResolutionEngineTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.6 conflict resolution tests.
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@Suite("Phase 7.6 conflict resolution")
struct ConflictResolutionEngineTests {
    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    @Test func concurrentDifferentPayloadRequiresReview() {
        let local = OperationEnvelope(
            identifier: "l",
            entityID: "task-1",
            entityType: "task",
            operationKind: "setStatus",
            lamportClock: 4,
            machineID: "mac-a",
            payload: ["status": "running"]
        )
        let remote = OperationEnvelope(
            identifier: "r",
            entityID: "task-1",
            entityType: "task",
            operationKind: "setStatus",
            lamportClock: 4,
            machineID: "mac-b",
            payload: ["status": "blocked"]
        )

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)

        #expect(outcome == .requiresReview(reason: "Concurrent non-commutative edits require review."))
    }

    @Test func auditAppendsRetainBothPayloads() {
        let local = OperationEnvelope(
            identifier: "l",
            entityID: "goal-1",
            entityType: "audit",
            operationKind: "appendAudit",
            lamportClock: 1,
            machineID: "mac-a",
            payload: ["line": "local"]
        )
        let remote = OperationEnvelope(
            identifier: "r",
            entityID: "goal-1",
            entityType: "audit",
            operationKind: "appendAudit",
            lamportClock: 1,
            machineID: "mac-b",
            payload: ["line": "remote"]
        )

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)

        #expect(
            outcome == .merged(
                payload: ["line": "local\nremote"],
                explanation: "Audit appends are commutative and both entries were retained."
            )
        )
    }

    @Test func newerLamportClockWinsForNonConcurrentEdits() {
        let local = OperationEnvelope(
            identifier: "l",
            entityID: "task-1",
            entityType: "task",
            operationKind: "setStatus",
            lamportClock: 5,
            machineID: "mac-a",
            payload: ["status": "completed"]
        )
        let remote = OperationEnvelope(
            identifier: "r",
            entityID: "task-1",
            entityType: "task",
            operationKind: "setStatus",
            lamportClock: 4,
            machineID: "mac-b",
            payload: ["status": "running"]
        )

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)

        #expect(
            outcome == .merged(
                payload: ["status": "completed"],
                explanation: "Local operation has the newer Lamport clock."
            )
        )
    }

    @Test func conflictPreviewDecodesRecordPayloadsAndRecommendsMerge() throws {
        let record = ConflictResolutionRecord(
            identifier: "conflict-1",
            entityID: "task-1",
            conflictKind: "setStatus",
            localPayloadJSON: """
            {"entityType":"task","operationKind":"appendAudit","machineID":"mac-a","lamportClock":"2","line":"local"}
            """,
            remotePayloadJSON: """
            {"entityType":"task","operationKind":"appendAudit","machineID":"mac-b","lamportClock":"2","line":"remote"}
            """
        )
        let snapshot = CloudSnapshotRecord(
            identifier: "snapshot-1",
            version: "1.0",
            scope: "SwiftData",
            recordCounts: "tasks=1",
            checksum: "abc",
            restoreNotes: "rollback",
            status: "available"
        )

        let preview = try #require(
            ConflictResolutionPreviewBuilder.preview(
                for: record,
                snapshots: [snapshot],
                now: Date(timeIntervalSince1970: 1_000)
            )
        )

        #expect(preview.entityID == "task-1")
        #expect(preview.recommendedAction == .merge)
        #expect(preview.proposedPayload["line"] == "local\nremote")
        #expect(preview.restoreSnapshotID == "snapshot-1")
        #expect(preview.affectedFieldCount == 1)
    }

    @Test func conflictDecisionPersistsResolutionWithoutMutatingTargetEntity() throws {
        let record = ConflictResolutionRecord(
            identifier: "conflict-2",
            entityID: "task-2",
            conflictKind: "setStatus",
            localPayloadJSON: #"{"entityType":"task","machineID":"mac-a","lamportClock":"4","status":"running"}"#,
            remotePayloadJSON: #"{"entityType":"task","machineID":"mac-b","lamportClock":"3","status":"blocked"}"#
        )
        let preview = try #require(ConflictResolutionPreviewBuilder.preview(for: record))

        try ConflictResolutionPreviewBuilder.apply(
            action: .keepLocal,
            to: record,
            using: preview,
            now: Date(timeIntervalSince1970: 2_000)
        )

        #expect(record.status == "resolved")
        #expect(record.resolvedAt != nil)
        #expect(record.resolutionJSON.contains("keepLocal"))
        #expect(record.resolutionJSON.contains("running"))
    }

    @Test func operationLogDivergenceCreatesSyntheticPreview() throws {
        let local = AutonomyOperationRecord(
            identifier: "op-local",
            entityID: "task-3",
            entityType: "task",
            operationKind: "setStatus",
            lamportClock: 8,
            machineID: "mac-a",
            payloadJSON: #"{"status":"running"}"#,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        let remote = AutonomyOperationRecord(
            identifier: "op-remote",
            entityID: "task-3",
            entityType: "task",
            operationKind: "setStatus",
            lamportClock: 8,
            machineID: "mac-b",
            payloadJSON: #"{"status":"blocked"}"#,
            createdAt: Date(timeIntervalSince1970: 1_900)
        )

        let previews = ConflictResolutionPreviewBuilder.build(
            records: [],
            operations: [local, remote],
            peers: [],
            snapshots: []
        )
        let preview = try #require(previews.first)

        #expect(preview.recordID == nil)
        #expect(preview.conflictKind == "operationLogDivergence")
        #expect(preview.recommendedAction == nil)
        #expect(preview.warnings.contains("No snapshot is available yet; create one before destructive resolution."))
    }

    @Test func syntheticPreviewCanCreateResolutionRecord() throws {
        let local = AutonomyOperationRecord(
            identifier: "op-local",
            entityID: "task-4",
            entityType: "task",
            operationKind: "setStatus",
            lamportClock: 11,
            machineID: "mac-a",
            payloadJSON: #"{"status":"running"}"#,
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
        let remote = AutonomyOperationRecord(
            identifier: "op-remote",
            entityID: "task-4",
            entityType: "task",
            operationKind: "setStatus",
            lamportClock: 11,
            machineID: "mac-b",
            payloadJSON: #"{"status":"blocked"}"#,
            createdAt: Date(timeIntervalSince1970: 2_900)
        )
        let preview = try #require(
            ConflictResolutionPreviewBuilder.build(
                records: [],
                operations: [local, remote],
                peers: [],
                snapshots: []
            )
            .first
        )

        let record = ConflictResolutionPreviewBuilder.makeRecord(
            from: preview,
            now: Date(timeIntervalSince1970: 3_100)
        )
        try ConflictResolutionPreviewBuilder.apply(action: .keepLocal, to: record, using: preview)

        #expect(record.entityID == "task-4")
        #expect(record.conflictKind == "operationLogDivergence")
        #expect(record.localPayloadJSON.contains("op-local"))
        #expect(record.remotePayloadJSON.contains("op-remote"))
        #expect(record.status == "resolved")
        #expect(record.resolutionJSON.contains("keepLocal"))
    }

    @Test func resolvedHistoricalRecordDoesNotHideNewSyntheticDivergence() throws {
        let resolved = ConflictResolutionRecord(
            identifier: "conflict-resolved",
            entityID: "task-6",
            conflictKind: "setStatus",
            status: "resolved"
        )
        let local = AutonomyOperationRecord(
            identifier: "op-local",
            entityID: "task-6",
            entityType: "task",
            operationKind: "setStatus",
            lamportClock: 12,
            machineID: "mac-a",
            payloadJSON: #"{"status":"running"}"#,
            createdAt: Date(timeIntervalSince1970: 4_000)
        )
        let remote = AutonomyOperationRecord(
            identifier: "op-remote",
            entityID: "task-6",
            entityType: "task",
            operationKind: "setStatus",
            lamportClock: 12,
            machineID: "mac-b",
            payloadJSON: #"{"status":"blocked"}"#,
            createdAt: Date(timeIntervalSince1970: 3_900)
        )

        let previews = ConflictResolutionPreviewBuilder.build(
            records: [resolved],
            operations: [local, remote],
            peers: [],
            snapshots: []
        )

        #expect(previews.contains { $0.recordID == nil && $0.entityID == "task-6" })
    }

    @Test func stalePeerWarningAppearsInPreview() throws {
        let record = ConflictResolutionRecord(
            identifier: "conflict-3",
            entityID: "task-5",
            conflictKind: "setStatus",
            localPayloadJSON: #"{"entityType":"task","machineID":"mac-a","lamportClock":"1","status":"running"}"#,
            remotePayloadJSON: #"{"entityType":"task","machineID":"mac-b","lamportClock":"1","status":"blocked"}"#
        )
        let peer = MachinePeerRecord(
            identifier: "mac-b",
            displayName: "Studio Mac",
            deviceFingerprintHash: "hash-b",
            lastSeenAt: Date(timeIntervalSince1970: 1_000)
        )

        let preview = try #require(
            ConflictResolutionPreviewBuilder.preview(
                for: record,
                peers: [peer],
                now: Date(timeIntervalSince1970: 8_000)
            )
        )

        #expect(preview.warnings.contains("Studio Mac: Peer needs snapshot verification before autonomous work."))
    }

    @Test func conflictRecoveryDrillMergesSafeHistoryAndPlansRestoreCopy() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let scenario = ConflictRecoveryDrill.makeScenario(runID: "drill-unit", now: now)

        let report = try ConflictRecoveryDrill.run(scenario: scenario, now: now)

        #expect(report.passed)
        #expect(report.appliedActions.contains(.merge))
        #expect(report.appliedActions.contains(.restoreIntoNewCopy))
        #expect(report.resolvedRecordIDs.contains("drill-unit-audit-conflict"))
        #expect(!report.restorePlannedRecordIDs.isEmpty)
        #expect(report.warnings.contains("Studio Mac: Peer needs snapshot verification before autonomous work."))
        #expect(report.createdSnapshotIDs == ["drill-unit-snapshot"])
    }

    // MARK: - Sprint Q.1: entity-specific merge policies

    @Test func providerProfilePolicyMergesDescriptiveFieldsAndPrefersLatestState() {
        let local = OperationEnvelope(
            identifier: "l",
            entityID: "openai.codex",
            entityType: EntityMergePolicyRegistry.providerProfile,
            operationKind: "updateProfile",
            lamportClock: 5,
            machineID: "mac-a",
            payload: [
                "identifier": "openai.codex",
                "providerFamily": "OpenAI",
                "binaryName": "codex",
                "capabilities": "",
                "installedState": "missing",
                "authState": "unauthenticated",
                "safetyNotes": "Existing local note",
            ]
        )
        let remote = OperationEnvelope(
            identifier: "r",
            entityID: "openai.codex",
            entityType: EntityMergePolicyRegistry.providerProfile,
            operationKind: "updateProfile",
            lamportClock: 7,
            machineID: "mac-b",
            payload: [
                "identifier": "openai.codex",
                "providerFamily": "OpenAI",
                "binaryName": "codex",
                "capabilities": "implementation, repair",
                "installedState": "available",
                "authState": "authenticated",
                "safetyNotes": "Existing local note",
            ]
        )

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)

        switch outcome {
        case .merged(let payload, let explanation):
            #expect(payload["capabilities"] == "implementation, repair")
            #expect(payload["installedState"] == "available")  // higher Lamport wins
            #expect(payload["authState"] == "authenticated")
            #expect(payload["safetyNotes"] == "Existing local note")
            #expect(explanation.contains("AgentProviderProfile merge policy"))
        case .requiresReview(let reason):
            Issue.record("Expected merge but got requiresReview: \(reason)")
        }
    }

    @Test func providerProfilePolicyHardConflictsOnImmutableIdentityChange() {
        let local = OperationEnvelope(
            identifier: "l",
            entityID: "openai.codex",
            entityType: EntityMergePolicyRegistry.providerProfile,
            operationKind: "updateProfile",
            lamportClock: 5,
            machineID: "mac-a",
            payload: [
                "identifier": "openai.codex",
                "providerFamily": "OpenAI",
                "binaryName": "codex",
            ]
        )
        let remote = OperationEnvelope(
            identifier: "r",
            entityID: "openai.codex",
            entityType: EntityMergePolicyRegistry.providerProfile,
            operationKind: "updateProfile",
            lamportClock: 6,
            machineID: "mac-b",
            payload: [
                "identifier": "openai.codex",
                "providerFamily": "OpenAI",
                "binaryName": "codex-next",  // immutable field changed → hard conflict
            ]
        )

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)

        if case .requiresReview(let reason) = outcome {
            #expect(reason.contains("binaryName"))
            #expect(reason.contains("AgentProviderProfile merge policy"))
        } else {
            Issue.record("Expected hard conflict on immutable binaryName change.")
        }
    }

    @Test func autonomyTaskPolicyKeepsTerminalStatusOverInProgress() {
        let local = OperationEnvelope(
            identifier: "l",
            entityID: "task-99",
            entityType: EntityMergePolicyRegistry.autonomyTask,
            operationKind: "setStatus",
            lamportClock: 5,
            machineID: "mac-a",
            payload: [
                "identifier": "task-99",
                "goalID": "goal-1",
                "status": "succeeded",
                "detail": "Local task summary",
            ]
        )
        let remote = OperationEnvelope(
            identifier: "r",
            entityID: "task-99",
            entityType: EntityMergePolicyRegistry.autonomyTask,
            operationKind: "setStatus",
            lamportClock: 8, // newer clock but non-terminal
            machineID: "mac-b",
            payload: [
                "identifier": "task-99",
                "goalID": "goal-1",
                "status": "inProgress",
                "detail": "Local task summary",
            ]
        )

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)

        if case .merged(let payload, _) = outcome {
            #expect(payload["status"] == "succeeded")
        } else {
            Issue.record("Expected terminal status to win over non-terminal regardless of clock.")
        }
    }

    @Test func autonomyTaskPolicyHardConflictsWhenBothStatusesAreTerminal() {
        let local = OperationEnvelope(
            identifier: "l",
            entityID: "task-99",
            entityType: EntityMergePolicyRegistry.autonomyTask,
            operationKind: "setStatus",
            lamportClock: 5,
            machineID: "mac-a",
            payload: [
                "identifier": "task-99",
                "goalID": "goal-1",
                "status": "succeeded",
            ]
        )
        let remote = OperationEnvelope(
            identifier: "r",
            entityID: "task-99",
            entityType: EntityMergePolicyRegistry.autonomyTask,
            operationKind: "setStatus",
            lamportClock: 6,
            machineID: "mac-b",
            payload: [
                "identifier": "task-99",
                "goalID": "goal-1",
                "status": "failed",
            ]
        )

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)

        if case .requiresReview(let reason) = outcome {
            #expect(reason.contains("status"))
            #expect(reason.contains("AutonomyTaskRecord merge policy"))
        } else {
            Issue.record("Expected hard conflict when both sides hold a different terminal status.")
        }
    }

    @Test func runOutcomePolicyKeepsUserRatingAndConcatsFeedbackLines() {
        let local = OperationEnvelope(
            identifier: "l",
            entityID: "run-1",
            entityType: EntityMergePolicyRegistry.runOutcome,
            operationKind: "updateOutcome",
            lamportClock: 4,
            machineID: "mac-a",
            payload: [
                "identifier": "run-1",
                "runID": "run-1",
                "providerID": "openai.codex",
                "buildResult": "exit0",
                "accuracyRating": "correct",
                "userFeedback": "Worked locally.",
                "status": "succeeded",
            ]
        )
        let remote = OperationEnvelope(
            identifier: "r",
            entityID: "run-1",
            entityType: EntityMergePolicyRegistry.runOutcome,
            operationKind: "updateOutcome",
            lamportClock: 6,
            machineID: "mac-b",
            payload: [
                "identifier": "run-1",
                "runID": "run-1",
                "providerID": "openai.codex",
                "buildResult": "exit0",
                "accuracyRating": "unrated",
                "userFeedback": "Worked from peer too.",
                "status": "succeeded",
            ]
        )

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)

        if case .merged(let payload, _) = outcome {
            #expect(payload["accuracyRating"] == "correct")
            #expect(payload["userFeedback"]?.contains("Worked locally.") == true)
            #expect(payload["userFeedback"]?.contains("Worked from peer too.") == true)
            #expect(payload["status"] == "succeeded")
        } else {
            Issue.record("Expected merge to preserve user rating and concat feedback lines.")
        }
    }

    @Test func runOutcomePolicyHardConflictsOnDivergentBuildResult() {
        let local = OperationEnvelope(
            identifier: "l",
            entityID: "run-1",
            entityType: EntityMergePolicyRegistry.runOutcome,
            operationKind: "updateOutcome",
            lamportClock: 5,
            machineID: "mac-a",
            payload: [
                "identifier": "run-1",
                "runID": "run-1",
                "providerID": "openai.codex",
                "buildResult": "exit0",
            ]
        )
        let remote = OperationEnvelope(
            identifier: "r",
            entityID: "run-1",
            entityType: EntityMergePolicyRegistry.runOutcome,
            operationKind: "updateOutcome",
            lamportClock: 6,
            machineID: "mac-b",
            payload: [
                "identifier": "run-1",
                "runID": "run-1",
                "providerID": "openai.codex",
                "buildResult": "exit1",
            ]
        )

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)

        if case .requiresReview(let reason) = outcome {
            #expect(reason.contains("buildResult"))
        } else {
            Issue.record("Expected hard conflict on divergent buildResult.")
        }
    }

    @Test func unknownEntityTypeFallsBackToGenericLamportArbitration() {
        // A novel entity type the policy registry doesn't know about
        // must keep working under the pre-Sprint-Q.1 Lamport rule.
        let local = OperationEnvelope(
            identifier: "l",
            entityID: "novel-1",
            entityType: "NovelEntityType",
            operationKind: "setSomething",
            lamportClock: 7,
            machineID: "mac-a",
            payload: ["field": "local"]
        )
        let remote = OperationEnvelope(
            identifier: "r",
            entityID: "novel-1",
            entityType: "NovelEntityType",
            operationKind: "setSomething",
            lamportClock: 9,
            machineID: "mac-b",
            payload: ["field": "remote"]
        )

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)

        if case .merged(let payload, let explanation) = outcome {
            #expect(payload["field"] == "remote")
            #expect(explanation.contains("Remote operation has the newer Lamport clock."))
        } else {
            Issue.record("Expected generic Lamport fallback for an unknown entity type.")
        }
    }

    @MainActor
    @Test func conflictRecoveryDrillPersistsSyntheticRecordsAndSnapshotAnchors() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 20_000)

        let report = try ConflictRecoveryDrill.seedAndRun(in: context, now: now)

        let conflicts = try context.fetch(FetchDescriptor<ConflictResolutionRecord>())
        let operations = try context.fetch(FetchDescriptor<AutonomyOperationRecord>())
        let peers = try context.fetch(FetchDescriptor<MachinePeerRecord>())
        let snapshots = try context.fetch(FetchDescriptor<CloudSnapshotRecord>())

        #expect(report.passed)
        #expect(conflicts.count == 2)
        #expect(conflicts.contains { $0.status == "resolved" && $0.resolutionJSON.contains("merge") })
        #expect(conflicts.contains { $0.status == "restorePlanned" && $0.resolutionJSON.contains("restoreIntoNewCopy") })
        #expect(operations.count == 2)
        #expect(peers.count == 2)
        #expect(snapshots.count == 1)
        #expect(conflicts.allSatisfy { $0.resolutionJSON.contains(report.runID) || $0.localPayloadJSON.contains(report.runID) })
    }
}
