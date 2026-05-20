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

enum ConflictResolutionOutcome: Sendable, Equatable, Hashable {
    case merged(payload: [String: String], explanation: String)
    case requiresReview(reason: String)
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
