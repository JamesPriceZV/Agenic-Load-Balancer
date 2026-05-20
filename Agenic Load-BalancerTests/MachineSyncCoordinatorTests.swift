//
//  MachineSyncCoordinatorTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.6 machine sync tests.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Phase 7.6 machine sync")
struct MachineSyncCoordinatorTests {
    @Test func recentPeerIsCurrent() {
        let now = Date(timeIntervalSince1970: 1_000)
        let status = MachineSyncCoordinator().classify(
            lastSeenAt: Date(timeIntervalSince1970: 900),
            now: now
        )

        #expect(status == .current)
    }

    @Test func stalePeerNeedsSnapshotVerification() {
        let now = Date(timeIntervalSince1970: 5_000)
        let status = MachineSyncCoordinator().classify(
            lastSeenAt: Date(timeIntervalSince1970: 1_000),
            now: now
        )

        #expect(status == .needsSnapshotVerification)
    }

    @Test func missingPeerNeedsSnapshotVerification() {
        let status = MachineSyncCoordinator().classify(lastSeenAt: nil, now: Date())

        #expect(status == .needsSnapshotVerification)
    }

    @Test func healthCarriesClassifiedStatus() {
        let now = Date(timeIntervalSince1970: 1_000)
        let health = MachineSyncCoordinator().health(
            machineID: "mac-a",
            displayName: "Mac A",
            lastSeenAt: Date(timeIntervalSince1970: 800),
            now: now
        )

        #expect(health.status == .current)
        #expect(health.machineID == "mac-a")
    }
}
