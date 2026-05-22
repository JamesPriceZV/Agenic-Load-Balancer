//
//  ConflictRecoveryDrill.swift
//  Agenic Load-Balancer
//
//  Sprint K: local multi-machine recovery drill for the Conflict Center.
//

import Foundation
import SwiftData

struct ConflictRecoveryDrillScenario {
    var runID: String
    var conflicts: [ConflictResolutionRecord]
    var operations: [AutonomyOperationRecord]
    var peers: [MachinePeerRecord]
    var snapshots: [CloudSnapshotRecord]
}

struct ConflictRecoveryDrillReport: Sendable, Hashable {
    var runID: String
    var createdOperationIDs: [String]
    var createdConflictIDs: [String]
    var createdPeerIDs: [String]
    var createdSnapshotIDs: [String]
    var appliedActions: [ConflictResolutionAction]
    var resolvedRecordIDs: [String]
    var restorePlannedRecordIDs: [String]
    var warnings: [String]
    var reportLines: [String]

    var passed: Bool {
        appliedActions.contains(.merge) &&
            appliedActions.contains(.restoreIntoNewCopy) &&
            !resolvedRecordIDs.isEmpty &&
            !restorePlannedRecordIDs.isEmpty
    }

    var summary: String {
        passed
            ? "Recovery drill passed: merged safe audit history and planned restore into new copy for risky task divergence."
            : "Recovery drill needs review: expected merge and restore plan were not both recorded."
    }
}

enum ConflictRecoveryDrill {
    static func makeScenario(
        runID: String = "drill-\(UUID().uuidString)",
        now: Date = Date()
    ) -> ConflictRecoveryDrillScenario {
        let localMachineID = "\(runID)-macbook"
        let remoteMachineID = "\(runID)-studio"
        let auditID = "\(runID)-audit"
        let taskID = "\(runID)-task"
        let snapshotID = "\(runID)-snapshot"

        let snapshot = CloudSnapshotRecord(
            identifier: snapshotID,
            version: "1.0",
            scope: "SwiftData",
            recordCounts: "autonomyOperations=2;conflicts=1",
            checksum: "drill-\(runID)",
            restoreNotes: "Synthetic rollback anchor for multi-machine recovery drill.",
            status: "available",
            createdAt: now.addingTimeInterval(-120)
        )

        let localPeer = MachinePeerRecord(
            identifier: localMachineID,
            displayName: "Local Mac",
            deviceFingerprintHash: "\(localMachineID)-hash",
            lastSeenAt: now.addingTimeInterval(-60),
            syncStatus: MachineSyncStatus.current.rawValue,
            createdAt: now.addingTimeInterval(-600),
            updatedAt: now.addingTimeInterval(-60)
        )

        let remotePeer = MachinePeerRecord(
            identifier: remoteMachineID,
            displayName: "Studio Mac",
            deviceFingerprintHash: "\(remoteMachineID)-hash",
            lastSeenAt: now.addingTimeInterval(-7_200),
            syncStatus: MachineSyncStatus.needsSnapshotVerification.rawValue,
            createdAt: now.addingTimeInterval(-600),
            updatedAt: now.addingTimeInterval(-7_200)
        )

        let auditConflict = ConflictResolutionRecord(
            identifier: "\(runID)-audit-conflict",
            entityID: auditID,
            conflictKind: "appendAudit",
            localPayloadJSON: envelopeJSON(
                identifier: "\(runID)-audit-local",
                entityID: auditID,
                entityType: "audit",
                operationKind: "appendAudit",
                lamportClock: 7,
                machineID: localMachineID,
                payload: [
                    "line": "Local Mac validated tests.",
                    "runID": runID,
                ]
            ),
            remotePayloadJSON: envelopeJSON(
                identifier: "\(runID)-audit-remote",
                entityID: auditID,
                entityType: "audit",
                operationKind: "appendAudit",
                lamportClock: 7,
                machineID: remoteMachineID,
                payload: [
                    "line": "Studio Mac refreshed snapshots.",
                    "runID": runID,
                ]
            ),
            createdAt: now.addingTimeInterval(-40)
        )

        let localTaskOperation = AutonomyOperationRecord(
            identifier: "\(runID)-task-local",
            entityID: taskID,
            entityType: "autonomyTask",
            operationKind: "setStatus",
            lamportClock: 12,
            machineID: localMachineID,
            payloadJSON: payloadJSON([
                "status": "running",
                "taskID": taskID,
                "runID": runID,
            ]),
            createdAt: now.addingTimeInterval(-30)
        )

        let remoteTaskOperation = AutonomyOperationRecord(
            identifier: "\(runID)-task-remote",
            entityID: taskID,
            entityType: "autonomyTask",
            operationKind: "setStatus",
            lamportClock: 12,
            machineID: remoteMachineID,
            payloadJSON: payloadJSON([
                "status": "blocked",
                "taskID": taskID,
                "runID": runID,
            ]),
            createdAt: now.addingTimeInterval(-20)
        )

        return ConflictRecoveryDrillScenario(
            runID: runID,
            conflicts: [auditConflict],
            operations: [localTaskOperation, remoteTaskOperation],
            peers: [localPeer, remotePeer],
            snapshots: [snapshot]
        )
    }

    static func run(
        scenario: ConflictRecoveryDrillScenario,
        now: Date = Date(),
        insertSyntheticRecord: (ConflictResolutionRecord) -> Void = { _ in }
    ) throws -> ConflictRecoveryDrillReport {
        let previews = ConflictResolutionPreviewBuilder.build(
            records: scenario.conflicts,
            operations: scenario.operations,
            peers: scenario.peers,
            snapshots: scenario.snapshots,
            now: now
        )

        var appliedActions: [ConflictResolutionAction] = []
        var resolvedRecordIDs: [String] = []
        var restorePlannedRecordIDs: [String] = []
        var createdConflictIDs = scenario.conflicts.map(\.identifier)
        var warnings: [String] = []
        var reportLines: [String] = []

        for preview in previews where preview.id.contains(scenario.runID) || preview.entityID.contains(scenario.runID) {
            warnings.append(contentsOf: preview.warnings)
            let record: ConflictResolutionRecord
            if let recordID = preview.recordID,
               let existing = scenario.conflicts.first(where: { $0.identifier == recordID }) {
                record = existing
            } else {
                record = ConflictResolutionPreviewBuilder.makeRecord(from: preview, now: now)
                createdConflictIDs.append(record.identifier)
                insertSyntheticRecord(record)
            }

            let action: ConflictResolutionAction
            if preview.conflictKind == "operationLogDivergence" {
                action = .restoreIntoNewCopy
            } else {
                action = preview.recommendedAction ?? .merge
            }

            try ConflictResolutionPreviewBuilder.apply(action: action, to: record, using: preview, now: now)
            appliedActions.append(action)
            switch record.status {
            case "resolved":
                resolvedRecordIDs.append(record.identifier)
            case "restorePlanned":
                restorePlannedRecordIDs.append(record.identifier)
            default:
                break
            }
            reportLines.append("\(action.label): \(preview.outcomeSummary)")
        }

        return ConflictRecoveryDrillReport(
            runID: scenario.runID,
            createdOperationIDs: scenario.operations.map(\.identifier),
            createdConflictIDs: createdConflictIDs,
            createdPeerIDs: scenario.peers.map(\.identifier),
            createdSnapshotIDs: scenario.snapshots.map(\.identifier),
            appliedActions: appliedActions,
            resolvedRecordIDs: resolvedRecordIDs,
            restorePlannedRecordIDs: restorePlannedRecordIDs,
            warnings: Array(Set(warnings)).sorted(),
            reportLines: reportLines
        )
    }

    @MainActor
    static func seedAndRun(
        in context: ModelContext,
        now: Date = Date()
    ) throws -> ConflictRecoveryDrillReport {
        let scenario = makeScenario(now: now)
        scenario.snapshots.forEach(context.insert)
        scenario.peers.forEach(context.insert)
        scenario.operations.forEach(context.insert)
        scenario.conflicts.forEach(context.insert)

        let report = try run(scenario: scenario, now: now) { record in
            context.insert(record)
        }
        try context.save()
        return report
    }

    private static func envelopeJSON(
        identifier: String,
        entityID: String,
        entityType: String,
        operationKind: String,
        lamportClock: Int,
        machineID: String,
        payload: [String: String]
    ) -> String {
        let envelope = OperationEnvelope(
            identifier: identifier,
            entityID: entityID,
            entityType: entityType,
            operationKind: operationKind,
            lamportClock: lamportClock,
            machineID: machineID,
            payload: payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func payloadJSON(_ payload: [String: String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
