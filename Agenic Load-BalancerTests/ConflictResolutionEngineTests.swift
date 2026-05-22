//
//  ConflictResolutionEngineTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.6 conflict resolution tests.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Phase 7.6 conflict resolution")
struct ConflictResolutionEngineTests {
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
}
