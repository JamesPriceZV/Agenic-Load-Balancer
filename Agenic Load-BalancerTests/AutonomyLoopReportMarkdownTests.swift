//
//  AutonomyLoopReportMarkdownTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint Q.9: pure Markdown renderer for persisted loop reports.
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@Suite("Sprint Q.9 loop report markdown renderer")
struct AutonomyLoopReportMarkdownTests {
    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    private static func encodeIterations(_ iterations: [AutonomousLoopIteration]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try String(data: encoder.encode(iterations), encoding: .utf8)!
    }

    private static func encodeStrings(_ values: [String]) throws -> String {
        try String(data: JSONEncoder().encode(values), encoding: .utf8)!
    }

    @MainActor
    @Test func renderProducesHeaderWithCoreFields() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let record = AutonomousLoopReportRecord(
            identifier: "report-md-1",
            goalID: "goal-md",
            planID: "plan-md",
            haltReasonKind: "completed",
            haltReasonLabel: "Plan walked to completion.",
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_010)
        )
        context.insert(record)
        try context.save()

        let md = AutonomyLoopReportMarkdown.render(record)
        #expect(md.hasPrefix("# Loop Report"))
        #expect(md.contains("- Plan: `plan-md`"))
        #expect(md.contains("- Goal: `goal-md`"))
        #expect(md.contains("- Halt reason: **completed**"))
        #expect(md.contains("Plan walked to completion."))
        #expect(md.hasSuffix("\n"))
    }

    @MainActor
    @Test func renderIncludesIterationsAndValidationTranscript() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let iterations = [
            AutonomousLoopIteration(
                index: 0,
                taskID: "task-a",
                taskTitle: "Inspect",
                mode: AgentExecutionMode.readReview.rawValue,
                status: .completedAdvisory,
                detail: "Advisory task; no provider required.",
                occurredAt: Date(timeIntervalSince1970: 2_000)
            ),
            AutonomousLoopIteration(
                index: 1,
                taskID: "task-b",
                taskTitle: "Run tests",
                mode: AgentExecutionMode.testBuild.rawValue,
                status: .validationFailed,
                detail: "Validation gate failed.",
                validationCommand: "swift test",
                validationExitCode: 1,
                validationOutputExcerpt: "XCTAssertEqual failed: \"a\" is not equal to \"b\"",
                occurredAt: Date(timeIntervalSince1970: 2_010)
            ),
        ]
        let record = AutonomousLoopReportRecord(
            identifier: "report-md-2",
            goalID: "goal-md",
            planID: "plan-md",
            haltReasonKind: "validationFailureCap",
            haltReasonLabel: "Validation failure cap (1) reached.",
            iterationsJSON: try Self.encodeIterations(iterations),
            validationFailureCount: 1,
            completedTaskIDsJSON: try Self.encodeStrings(["task-a"]),
            pendingTaskIDsJSON: try Self.encodeStrings(["task-b"])
        )
        context.insert(record)
        try context.save()

        let md = AutonomyLoopReportMarkdown.render(record)
        #expect(md.contains("## Iterations"))
        #expect(md.contains("### #0 — Inspect (completedAdvisory)"))
        #expect(md.contains("### #1 — Run tests (validationFailed)"))
        #expect(md.contains("- Validation: `swift test` → exit 1"))
        #expect(md.contains("```text"))
        #expect(md.contains("XCTAssertEqual failed"))
        #expect(md.contains("## Task Roll-Up"))
        #expect(md.contains("- Completed: `task-a`"))
        #expect(md.contains("- Pending: `task-b`"))
    }

    @MainActor
    @Test func renderHandlesEmptyIterationsAndEmptyRollup() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let record = AutonomousLoopReportRecord(
            identifier: "report-md-3",
            goalID: "goal-md",
            planID: "plan-md",
            haltReasonKind: "completed",
            haltReasonLabel: "Plan walked to completion."
        )
        context.insert(record)
        try context.save()

        let md = AutonomyLoopReportMarkdown.render(record)
        #expect(md.contains("_No iterations were recorded for this walk._"))
        #expect(md.contains("- Completed: _none_"))
        #expect(md.contains("- Pending: _none_"))
    }

    @MainActor
    @Test func renderOmitsTranscriptBlockWhenExcerptIsAbsent() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let iteration = AutonomousLoopIteration(
            index: 0,
            taskID: "task-a",
            taskTitle: "Run tests",
            mode: AgentExecutionMode.testBuild.rawValue,
            status: .validationPassed,
            detail: "passed",
            validationCommand: "swift test",
            validationExitCode: 0,
            occurredAt: Date(timeIntervalSince1970: 3_000)
        )
        let record = AutonomousLoopReportRecord(
            identifier: "report-md-4",
            goalID: "goal-md",
            planID: "plan-md",
            haltReasonKind: "completed",
            haltReasonLabel: "Plan walked to completion.",
            iterationsJSON: try Self.encodeIterations([iteration])
        )
        context.insert(record)
        try context.save()

        let md = AutonomyLoopReportMarkdown.render(record)
        #expect(md.contains("- Validation: `swift test` → exit 0"))
        #expect(!md.contains("```text"))
    }
}
