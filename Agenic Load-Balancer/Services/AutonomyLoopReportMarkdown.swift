//
//  AutonomyLoopReportMarkdown.swift
//  Agenic Load-Balancer
//
//  Sprint Q.9: render a persisted `AutonomousLoopReportRecord` as
//  Markdown so the user can paste a report straight into a GitHub
//  issue, a PR, or `AgentNotes.md`. The renderer is pure, reads no
//  global state, and never touches SwiftData beyond the record it is
//  handed — same contract as the JSON encoder in Q.6.
//

import Foundation

enum AutonomyLoopReportMarkdown {
    static func render(_ report: AutonomousLoopReportRecord) -> String {
        let iterations = AutonomousLoopPersistence.decodeIterations(report.iterationsJSON)
        let completed = AutonomousLoopPersistence.decodeTaskIDs(report.completedTaskIDsJSON)
        let pending = AutonomousLoopPersistence.decodeTaskIDs(report.pendingTaskIDsJSON)
        let iso = ISO8601DateFormatter()

        var lines: [String] = []
        lines.append("# Loop Report")
        lines.append("")
        lines.append("- Plan: `\(report.planID)`")
        lines.append("- Goal: `\(report.goalID)`")
        lines.append("- Halt reason: **\(report.haltReasonKind)** — \(report.haltReasonLabel)")
        lines.append("- Started: \(iso.string(from: report.startedAt))")
        lines.append("- Ended: \(iso.string(from: report.endedAt))")
        lines.append("- Iterations: \(iterations.count) · Failures: \(report.validationFailureCount) · Approvals: \(report.approvalSurfaceCount)")
        lines.append("")

        if iterations.isEmpty {
            lines.append("_No iterations were recorded for this walk._")
        } else {
            lines.append("## Iterations")
            lines.append("")
            for iteration in iterations {
                lines.append(contentsOf: renderIteration(iteration, iso: iso))
                lines.append("")
            }
        }

        lines.append("## Task Roll-Up")
        lines.append("")
        lines.append(renderRollup(label: "Completed", ids: completed))
        lines.append(renderRollup(label: "Pending", ids: pending))

        // Trailing newline keeps the rendered output friendly when
        // pasted into a Markdown file that already ends without one.
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderIteration(
        _ iteration: AutonomousLoopIteration,
        iso: ISO8601DateFormatter
    ) -> [String] {
        var lines: [String] = []
        lines.append("### #\(iteration.index) — \(iteration.taskTitle) (\(iteration.status.rawValue))")
        lines.append("")
        lines.append("- Task: `\(iteration.taskID)`")
        lines.append("- Mode: \(iteration.mode)")
        lines.append("- Detail: \(iteration.detail)")
        if let command = iteration.validationCommand, !command.isEmpty {
            let exitText = iteration.validationExitCode.map { "exit \($0)" } ?? "no exit code"
            lines.append("- Validation: `\(command)` → \(exitText)")
            if let excerpt = iteration.validationOutputExcerpt, !excerpt.isEmpty {
                lines.append("")
                lines.append("```text")
                lines.append(excerpt)
                lines.append("```")
            }
        }
        lines.append("- At: \(iso.string(from: iteration.occurredAt))")
        return lines
    }

    private static func renderRollup(label: String, ids: [String]) -> String {
        if ids.isEmpty {
            return "- \(label): _none_"
        }
        let backticked = ids.map { "`\($0)`" }.joined(separator: ", ")
        return "- \(label): \(backticked)"
    }
}
