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
}
