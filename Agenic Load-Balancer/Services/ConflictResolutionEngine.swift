//
//  ConflictResolutionEngine.swift
//  Agenic Load-Balancer
//
//  Phase 7.6: deterministic operation-log conflict handling.
//

import Foundation

struct OperationEnvelope: Sendable, Codable, Hashable {
    var identifier: String
    var entityID: String
    var entityType: String
    var operationKind: String
    var lamportClock: Int
    var machineID: String
    var payload: [String: String]
}

enum ConflictResolutionAction: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case keepLocal
    case acceptRemote
    case merge
    case restoreSnapshot
    case restoreIntoNewCopy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keepLocal: "Keep Local"
        case .acceptRemote: "Accept Remote"
        case .merge: "Merge"
        case .restoreSnapshot: "Restore Snapshot"
        case .restoreIntoNewCopy: "New Copy"
        }
    }

    var detail: String {
        switch self {
        case .keepLocal: "Prefer the local operation payload."
        case .acceptRemote: "Prefer the remote operation payload."
        case .merge: "Use the deterministic merged payload when available."
        case .restoreSnapshot: "Plan a restore from an existing snapshot before replacing live state."
        case .restoreIntoNewCopy: "Plan a restore into a separate local copy before touching live state."
        }
    }

    var isRestoreLane: Bool {
        switch self {
        case .restoreSnapshot, .restoreIntoNewCopy:
            return true
        case .keepLocal, .acceptRemote, .merge:
            return false
        }
    }
}

enum ConflictResolutionOutcome: Sendable, Equatable, Hashable {
    case merged(payload: [String: String], explanation: String)
    case requiresReview(reason: String)
}

struct ConflictResolutionPreview: Identifiable, Sendable, Hashable {
    let id: String
    let recordID: String?
    let entityID: String
    let entityType: String
    let conflictKind: String
    let status: String
    let local: OperationEnvelope
    let remote: OperationEnvelope
    let localCreatedAt: Date
    let remoteCreatedAt: Date
    let affectedEntityCount: Int
    let affectedFieldCount: Int
    let sourceRunID: String?
    let sourceTaskID: String?
    let sourcePlanID: String?
    let restoreSnapshotID: String?
    let outcomeSummary: String
    let recommendedAction: ConflictResolutionAction?
    let proposedPayload: [String: String]
    let warnings: [String]
    let resolutionJSON: String
    let createdAt: Date

    var isOpen: Bool {
        status != "resolved" && status != "restorePlanned"
    }
}

struct ConflictResolutionDecision: Sendable, Codable, Hashable {
    var action: ConflictResolutionAction
    var entityID: String
    var entityType: String
    var selectedPayload: [String: String]
    var explanation: String
    var restoreSnapshotID: String?
    var decidedAt: Date
}

struct ConflictResolutionEngine: Sendable {
    func resolve(local: OperationEnvelope, remote: OperationEnvelope) -> ConflictResolutionOutcome {
        guard local.entityID == remote.entityID, local.entityType == remote.entityType else {
            return .requiresReview(reason: "Operations target different entities.")
        }

        if local.operationKind == "appendAudit" && remote.operationKind == "appendAudit" {
            let merged = local.payload.merging(remote.payload) { left, right in
                [left, right].sorted().joined(separator: "\n")
            }
            return .merged(
                payload: merged,
                explanation: "Audit appends are commutative and both entries were retained."
            )
        }

        // Sprint Q.1: consult the entity-specific merge policy first.
        // The policy can produce a deterministic merged payload for safe
        // fields (preferNonEmpty, preferLatest, concatLines,
        // stateMachineFavorTerminal, userRatedWinsOverInferred) or a
        // precise hard-conflict marker naming the offending fields. The
        // generic Lamport-clock arbitration below is the fallback for
        // entity types the policy registry doesn't yet know about.
        if let policy = EntityMergePolicyRegistry.policy(for: local.entityType) {
            switch EntityMergePolicyEvaluator.evaluate(policy: policy, local: local, remote: remote) {
            case .merged(let payload, let explanation):
                return .merged(
                    payload: payload,
                    explanation: "\(local.entityType) merge policy: \(explanation)"
                )
            case .hardConflict(_, let reason):
                return .requiresReview(reason: "\(local.entityType) merge policy: \(reason)")
            case .notApplicable:
                break
            }
        }

        if local.lamportClock == remote.lamportClock && local.payload != remote.payload {
            return .requiresReview(reason: "Concurrent non-commutative edits require review.")
        }

        if local.lamportClock == remote.lamportClock {
            return .merged(payload: local.payload, explanation: "Concurrent operations had identical payloads.")
        }

        return local.lamportClock > remote.lamportClock
            ? .merged(payload: local.payload, explanation: "Local operation has the newer Lamport clock.")
            : .merged(payload: remote.payload, explanation: "Remote operation has the newer Lamport clock.")
    }
}

enum ConflictResolutionPreviewBuilder {
    static func build(
        records: [ConflictResolutionRecord],
        operations: [AutonomyOperationRecord],
        peers: [MachinePeerRecord],
        snapshots: [CloudSnapshotRecord],
        now: Date = Date()
    ) -> [ConflictResolutionPreview] {
        let recordPreviews = records.compactMap { record in
            preview(for: record, operations: operations, peers: peers, snapshots: snapshots, now: now)
        }
        let openRecordEntityIDs = Set(recordPreviews.filter(\.isOpen).map(\.entityID))
        let operationPreviews = divergentOperationPreviews(
            operations: operations,
            peers: peers,
            snapshots: snapshots,
            excludedEntityIDs: openRecordEntityIDs,
            now: now
        )

        return (recordPreviews + operationPreviews)
            .sorted { lhs, rhs in
                if lhs.isOpen != rhs.isOpen { return lhs.isOpen && !rhs.isOpen }
                return lhs.createdAt > rhs.createdAt
            }
    }

    static func preview(
        for record: ConflictResolutionRecord,
        operations: [AutonomyOperationRecord] = [],
        peers: [MachinePeerRecord] = [],
        snapshots: [CloudSnapshotRecord] = [],
        now: Date = Date()
    ) -> ConflictResolutionPreview? {
        let matchingOperations = operations.filter { $0.entityID == record.entityID }
        let local = envelope(
            from: record.localPayloadJSON,
            fallbackIdentifier: "\(record.identifier):local",
            fallbackEntityID: record.entityID,
            fallbackEntityType: entityType(from: record.conflictKind),
            fallbackOperationKind: record.conflictKind,
            fallbackMachineID: "local",
            fallbackClock: matchingOperations.map(\.lamportClock).max() ?? 0
        )
        let remote = envelope(
            from: record.remotePayloadJSON,
            fallbackIdentifier: "\(record.identifier):remote",
            fallbackEntityID: record.entityID,
            fallbackEntityType: local.entityType,
            fallbackOperationKind: local.operationKind,
            fallbackMachineID: "remote",
            fallbackClock: max(0, local.lamportClock)
        )
        let localCreatedAt = matchingOperations
            .filter { $0.machineID == local.machineID || $0.identifier == local.identifier }
            .map(\.createdAt)
            .max() ?? record.createdAt
        let remoteCreatedAt = matchingOperations
            .filter { $0.machineID == remote.machineID || $0.identifier == remote.identifier }
            .map(\.createdAt)
            .max() ?? record.createdAt

        return makePreview(
            id: record.identifier,
            recordID: record.identifier,
            entityID: record.entityID,
            conflictKind: record.conflictKind,
            status: record.status,
            local: local,
            remote: remote,
            localCreatedAt: localCreatedAt,
            remoteCreatedAt: remoteCreatedAt,
            createdAt: record.createdAt,
            peers: peers,
            snapshots: snapshots,
            now: now
        )
    }

    static func apply(
        action: ConflictResolutionAction,
        to record: ConflictResolutionRecord,
        using preview: ConflictResolutionPreview,
        now: Date = Date()
    ) throws {
        let selectedPayload = payload(for: action, preview: preview)
        let decision = ConflictResolutionDecision(
            action: action,
            entityID: preview.entityID,
            entityType: preview.entityType,
            selectedPayload: selectedPayload,
            explanation: explanation(for: action, preview: preview),
            restoreSnapshotID: preview.restoreSnapshotID,
            decidedAt: now
        )
        record.resolutionJSON = try encodeDecision(decision)
        record.status = action.isRestoreLane ? "restorePlanned" : "resolved"
        record.resolvedAt = now
    }

    static func makeRecord(
        from preview: ConflictResolutionPreview,
        now: Date = Date()
    ) -> ConflictResolutionRecord {
        ConflictResolutionRecord(
            identifier: preview.recordID ?? UUID().uuidString,
            entityID: preview.entityID,
            conflictKind: preview.conflictKind,
            status: "open",
            localPayloadJSON: encodeEnvelope(preview.local),
            remotePayloadJSON: encodeEnvelope(preview.remote),
            resolutionJSON: preview.resolutionJSON,
            createdAt: now
        )
    }

    private static func divergentOperationPreviews(
        operations: [AutonomyOperationRecord],
        peers: [MachinePeerRecord],
        snapshots: [CloudSnapshotRecord],
        excludedEntityIDs: Set<String>,
        now: Date
    ) -> [ConflictResolutionPreview] {
        let grouped = Dictionary(grouping: operations) { operation in
            "\(operation.entityType)::\(operation.entityID)"
        }

        return grouped.compactMap { _, operations in
            guard operations.count >= 2 else { return nil }
            let sorted = operations.sorted { $0.createdAt > $1.createdAt }
            guard let localOperation = sorted.first else { return nil }
            guard let remoteOperation = sorted.first(where: {
                $0.identifier != localOperation.identifier &&
                    ($0.machineID != localOperation.machineID || $0.payloadJSON != localOperation.payloadJSON)
            }) else { return nil }
            guard !excludedEntityIDs.contains(localOperation.entityID) else { return nil }

            let local = envelope(from: localOperation)
            let remote = envelope(from: remoteOperation)
            let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)
            guard case .requiresReview = outcome else { return nil }

            return makePreview(
                id: "operation:\(localOperation.identifier):\(remoteOperation.identifier)",
                recordID: nil,
                entityID: localOperation.entityID,
                conflictKind: "operationLogDivergence",
                status: "open",
                local: local,
                remote: remote,
                localCreatedAt: localOperation.createdAt,
                remoteCreatedAt: remoteOperation.createdAt,
                createdAt: max(localOperation.createdAt, remoteOperation.createdAt),
                peers: peers,
                snapshots: snapshots,
                now: now
            )
        }
    }

    private static func makePreview(
        id: String,
        recordID: String?,
        entityID: String,
        conflictKind: String,
        status: String,
        local: OperationEnvelope,
        remote: OperationEnvelope,
        localCreatedAt: Date,
        remoteCreatedAt: Date,
        createdAt: Date,
        peers: [MachinePeerRecord],
        snapshots: [CloudSnapshotRecord],
        now: Date
    ) -> ConflictResolutionPreview {
        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)
        let latestSnapshotID = snapshots.sorted { $0.createdAt > $1.createdAt }.first?.identifier
        let recommendedAction: ConflictResolutionAction?
        let proposedPayload: [String: String]
        let outcomeSummary: String

        switch outcome {
        case .merged(let payload, let explanation):
            recommendedAction = .merge
            proposedPayload = payload
            outcomeSummary = explanation
        case .requiresReview(let reason):
            recommendedAction = local.lamportClock > remote.lamportClock
                ? .keepLocal
                : (remote.lamportClock > local.lamportClock ? .acceptRemote : nil)
            proposedPayload = [:]
            outcomeSummary = reason
        }

        let fieldKeys = Set(local.payload.keys).union(remote.payload.keys)
        let peerWarnings = stalePeerWarnings(
            peerIDs: [local.machineID, remote.machineID],
            peers: peers,
            now: now
        )
        let snapshotWarnings = latestSnapshotID == nil
            ? ["No snapshot is available yet; create one before destructive resolution."]
            : []

        return ConflictResolutionPreview(
            id: id,
            recordID: recordID,
            entityID: entityID,
            entityType: local.entityType,
            conflictKind: conflictKind,
            status: status,
            local: local,
            remote: remote,
            localCreatedAt: localCreatedAt,
            remoteCreatedAt: remoteCreatedAt,
            affectedEntityCount: local.entityID == remote.entityID ? 1 : 2,
            affectedFieldCount: fieldKeys.count,
            sourceRunID: local.payload["runID"] ?? remote.payload["runID"],
            sourceTaskID: local.payload["taskID"] ?? remote.payload["taskID"],
            sourcePlanID: local.payload["planID"] ?? remote.payload["planID"],
            restoreSnapshotID: latestSnapshotID,
            outcomeSummary: outcomeSummary,
            recommendedAction: recommendedAction,
            proposedPayload: proposedPayload,
            warnings: peerWarnings + snapshotWarnings,
            resolutionJSON: resolutionJSON(
                action: recommendedAction ?? .keepLocal,
                preview: ConflictResolutionPreviewSeed(
                    entityID: entityID,
                    entityType: local.entityType,
                    proposedPayload: proposedPayload,
                    restoreSnapshotID: latestSnapshotID,
                    outcomeSummary: outcomeSummary
                ),
                now: now
            ),
            createdAt: createdAt
        )
    }

    private struct ConflictResolutionPreviewSeed {
        var entityID: String
        var entityType: String
        var proposedPayload: [String: String]
        var restoreSnapshotID: String?
        var outcomeSummary: String
    }

    private static func payload(for action: ConflictResolutionAction, preview: ConflictResolutionPreview) -> [String: String] {
        switch action {
        case .keepLocal:
            return preview.local.payload
        case .acceptRemote:
            return preview.remote.payload
        case .merge:
            return preview.proposedPayload.isEmpty
                ? preview.local.payload.merging(preview.remote.payload) { local, _ in local }
                : preview.proposedPayload
        case .restoreSnapshot, .restoreIntoNewCopy:
            return [
                "restoreSnapshotID": preview.restoreSnapshotID ?? "",
                "entityID": preview.entityID,
                "entityType": preview.entityType,
            ]
        }
    }

    private static func explanation(for action: ConflictResolutionAction, preview: ConflictResolutionPreview) -> String {
        "\(action.label): \(action.detail) \(preview.outcomeSummary)"
    }

    private static func resolutionJSON(
        action: ConflictResolutionAction,
        preview: ConflictResolutionPreviewSeed,
        now: Date
    ) -> String {
        let decision = ConflictResolutionDecision(
            action: action,
            entityID: preview.entityID,
            entityType: preview.entityType,
            selectedPayload: preview.proposedPayload,
            explanation: preview.outcomeSummary,
            restoreSnapshotID: preview.restoreSnapshotID,
            decidedAt: now
        )
        return (try? encodeDecision(decision)) ?? "{}"
    }

    private static func encodeDecision(_ decision: ConflictResolutionDecision) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(decision)
        return String(decoding: data, as: UTF8.self)
    }

    private static func encodeEnvelope(_ envelope: OperationEnvelope) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func stalePeerWarnings(
        peerIDs: [String],
        peers: [MachinePeerRecord],
        now: Date
    ) -> [String] {
        peerIDs.compactMap { peerID in
            guard let peer = peers.first(where: { $0.identifier == peerID || $0.deviceFingerprintHash == peerID || $0.displayName == peerID }) else {
                return nil
            }
            let health = MachineSyncCoordinator().health(
                machineID: peer.identifier,
                displayName: peer.displayName,
                lastSeenAt: peer.lastSeenAt,
                now: now
            )
            return health.status == .current
                ? nil
                : "\(peer.displayName): \(health.detail)"
        }
    }

    private static func envelope(from operation: AutonomyOperationRecord) -> OperationEnvelope {
        envelope(
            from: operation.payloadJSON,
            fallbackIdentifier: operation.identifier,
            fallbackEntityID: operation.entityID,
            fallbackEntityType: operation.entityType,
            fallbackOperationKind: operation.operationKind,
            fallbackMachineID: operation.machineID,
            fallbackClock: operation.lamportClock
        )
    }

    private static func envelope(
        from json: String,
        fallbackIdentifier: String,
        fallbackEntityID: String,
        fallbackEntityType: String,
        fallbackOperationKind: String,
        fallbackMachineID: String,
        fallbackClock: Int
    ) -> OperationEnvelope {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(OperationEnvelope.self, from: data) {
            return decoded
        }

        let payload = decodePayload(from: data)
        let entityID = payload["entityID"] ?? fallbackEntityID
        let entityType = payload["entityType"] ?? fallbackEntityType
        let operationKind = payload["operationKind"] ?? fallbackOperationKind
        let machineID = payload["machineID"] ?? fallbackMachineID
        let lamportClock = Int(payload["lamportClock"] ?? "") ?? fallbackClock
        let identifier = payload["identifier"] ?? fallbackIdentifier
        return OperationEnvelope(
            identifier: identifier,
            entityID: entityID,
            entityType: entityType,
            operationKind: operationKind,
            lamportClock: lamportClock,
            machineID: machineID,
            payload: payload.filter { key, _ in
                !["identifier", "entityID", "entityType", "operationKind", "machineID", "lamportClock"].contains(key)
            }
        )
    }

    private static func decodePayload(from data: Data) -> [String: String] {
        if let strings = try? JSONDecoder().decode([String: String].self, from: data) {
            return strings
        }
        guard
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return raw.compactMapValues { value in
            switch value {
            case let string as String:
                return string
            case let number as NSNumber:
                return number.stringValue
            case let bool as Bool:
                return bool ? "true" : "false"
            default:
                return nil
            }
        }
    }

    private static func entityType(from conflictKind: String) -> String {
        if conflictKind.localizedCaseInsensitiveContains("task") { return "task" }
        if conflictKind.localizedCaseInsensitiveContains("project") { return "project" }
        if conflictKind.localizedCaseInsensitiveContains("provider") { return "provider" }
        if conflictKind.localizedCaseInsensitiveContains("snapshot") { return "snapshot" }
        return "operation"
    }
}
