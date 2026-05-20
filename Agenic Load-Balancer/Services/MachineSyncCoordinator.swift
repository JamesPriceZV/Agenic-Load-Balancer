//
//  MachineSyncCoordinator.swift
//  Agenic Load-Balancer
//
//  Phase 7.6: cross-machine sync health classification.
//

import Foundation

enum MachineSyncStatus: String, Sendable, Codable, Hashable {
    case current
    case delayed
    case divergent
    case needsSnapshotVerification
}

struct MachineSyncHealth: Sendable, Codable, Hashable {
    var machineID: String
    var displayName: String
    var status: MachineSyncStatus
    var lastSeenAt: Date?
    var detail: String
}

struct MachineSyncCoordinator: Sendable {
    func classify(lastSeenAt: Date?, now: Date = Date()) -> MachineSyncStatus {
        guard let lastSeenAt else { return .needsSnapshotVerification }
        let age = now.timeIntervalSince(lastSeenAt)
        if age < 0 { return .needsSnapshotVerification }
        if age < 300 { return .current }
        if age < 3_600 { return .delayed }
        return .needsSnapshotVerification
    }

    func health(
        machineID: String,
        displayName: String,
        lastSeenAt: Date?,
        now: Date = Date()
    ) -> MachineSyncHealth {
        let status = classify(lastSeenAt: lastSeenAt, now: now)
        return MachineSyncHealth(
            machineID: machineID,
            displayName: displayName,
            status: status,
            lastSeenAt: lastSeenAt,
            detail: detail(for: status)
        )
    }

    private func detail(for status: MachineSyncStatus) -> String {
        switch status {
        case .current: "Peer recently synced."
        case .delayed: "Peer has not synced recently."
        case .divergent: "Peer reports divergent operation logs."
        case .needsSnapshotVerification: "Peer needs snapshot verification before autonomous work."
        }
    }
}
