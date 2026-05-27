//
//  AutonomyLoopReportDetailTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint Q.6: drill-down view for persisted scheduler reports.
//  Coverage is pure (no SwiftUI rendering): the filter behavior and
//  the JSON encoder used by the "Copy JSON" button.
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@Suite("Sprint Q.6 loop report detail")
struct AutonomyLoopReportDetailTests {
    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    private static func iteration(
        index: Int,
        status: AutonomousLoopIteration.Status,
        validationExitCode: Int32? = nil,
        validationCommand: String? = nil
    ) -> AutonomousLoopIteration {
        AutonomousLoopIteration(
            index: index,
            taskID: "task-\(index)",
            taskTitle: "Task \(index)",
            mode: AgentExecutionMode.implementation.rawValue,
            status: status,
            detail: "iteration \(index)",
            validationCommand: validationCommand,
            validationExitCode: validationExitCode,
            occurredAt: Date(timeIntervalSince1970: TimeInterval(2_000 + index))
        )
    }

    @Test func filterAllReturnsEveryIteration() {
        let iterations = [
            Self.iteration(index: 0, status: .completedAdvisory),
            Self.iteration(index: 1, status: .validationPassed),
            Self.iteration(index: 2, status: .validationFailed),
            Self.iteration(index: 3, status: .approvalRequired),
            Self.iteration(index: 4, status: .denied),
            Self.iteration(index: 5, status: .dependenciesUnresolved),
        ]
        let result = AutonomyLoopReportFilter.all.apply(to: iterations)
        #expect(result.count == 6)
    }

    @Test func filterFailuresOnlyReturnsFailureLikeIterations() {
        let iterations = [
            Self.iteration(index: 0, status: .completedAdvisory),
            Self.iteration(index: 1, status: .validationPassed),
            Self.iteration(index: 2, status: .validationFailed),
            Self.iteration(index: 3, status: .approvalRequired),
            Self.iteration(index: 4, status: .denied),
            Self.iteration(index: 5, status: .dependenciesUnresolved),
        ]
        let result = AutonomyLoopReportFilter.failuresOnly.apply(to: iterations)
        let statuses = result.map(\.status)
        #expect(statuses == [.validationFailed, .denied, .dependenciesUnresolved])
    }

    @Test func filterApprovalsOnlyReturnsOnlyApprovalIterations() {
        let iterations = [
            Self.iteration(index: 0, status: .validationPassed),
            Self.iteration(index: 1, status: .approvalRequired),
            Self.iteration(index: 2, status: .approvalRequired),
            Self.iteration(index: 3, status: .denied),
        ]
        let result = AutonomyLoopReportFilter.approvalsOnly.apply(to: iterations)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.status == .approvalRequired })
    }

    @Test func filterValidationOnlyReturnsBothPassedAndFailed() {
        let iterations = [
            Self.iteration(index: 0, status: .completedAdvisory),
            Self.iteration(index: 1, status: .validationPassed),
            Self.iteration(index: 2, status: .validationFailed),
            Self.iteration(index: 3, status: .approvalRequired),
        ]
        let result = AutonomyLoopReportFilter.validationOnly.apply(to: iterations)
        let statuses = result.map(\.status)
        #expect(statuses == [.validationPassed, .validationFailed])
    }

    @MainActor
    @Test func jsonEncoderRoundTripsPersistedReport() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let iterations = [
            Self.iteration(index: 0, status: .completedAdvisory),
            Self.iteration(index: 1, status: .validationFailed, validationExitCode: 1, validationCommand: "echo fail"),
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let iterationsJSON = try String(data: encoder.encode(iterations), encoding: .utf8)!

        let record = AutonomousLoopReportRecord(
            identifier: "report-1",
            goalID: "goal-1",
            planID: "plan-1",
            haltReasonKind: "validationFailureCap",
            haltReasonLabel: "Validation failure cap (1) reached.",
            iterationsJSON: iterationsJSON,
            validationFailureCount: 1,
            approvalSurfaceCount: 0,
            completedTaskIDsJSON: #"["task-0"]"#,
            pendingTaskIDsJSON: #"["task-1"]"#,
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 2_010)
        )
        context.insert(record)
        try context.save()

        let json = AutonomyLoopReportJSON.encode(record)
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        #expect(parsed["identifier"] as? String == "report-1")
        #expect(parsed["goalID"] as? String == "goal-1")
        #expect(parsed["planID"] as? String == "plan-1")
        #expect(parsed["haltReasonKind"] as? String == "validationFailureCap")
        #expect(parsed["validationFailureCount"] as? Int == 1)
        #expect(parsed["approvalSurfaceCount"] as? Int == 0)

        let iterationsParsed = try #require(parsed["iterations"] as? [[String: Any]])
        #expect(iterationsParsed.count == 2)
        let second = iterationsParsed[1]
        #expect(second["status"] as? String == "validationFailed")
        #expect(second["validationCommand"] as? String == "echo fail")
        #expect(second["validationExitCode"] as? Int == 1)

        let completed = try #require(parsed["completedTaskIDs"] as? [String])
        #expect(completed == ["task-0"])
        let pending = try #require(parsed["pendingTaskIDs"] as? [String])
        #expect(pending == ["task-1"])
    }

    @MainActor
    @Test func jsonEncoderEmitsEmptyArraysForRecordWithNoIterations() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let record = AutonomousLoopReportRecord(
            identifier: "report-empty",
            goalID: "goal-x",
            planID: "plan-x",
            haltReasonKind: "completed",
            haltReasonLabel: "Plan walked to completion."
        )
        context.insert(record)
        try context.save()

        let json = AutonomyLoopReportJSON.encode(record)
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        let iterations = try #require(parsed["iterations"] as? [[String: Any]])
        #expect(iterations.isEmpty)
        let completed = try #require(parsed["completedTaskIDs"] as? [String])
        #expect(completed.isEmpty)
    }
}
