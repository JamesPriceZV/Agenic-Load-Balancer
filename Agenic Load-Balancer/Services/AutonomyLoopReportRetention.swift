//
//  AutonomyLoopReportRetention.swift
//  Agenic Load-Balancer
//
//  Sprint Q.10: bound the persisted `AutonomousLoopReportRecord`
//  store so a long-running developer doesn't accumulate thousands of
//  scheduler reports. The policy:
//
//   - Always preserves the most recent report per `planID`. The
//     Autonomy control room's Loop History panel becomes useless if
//     "the latest one" can vanish.
//   - Beyond that, keeps at most `maxReportsPerPlan` reports for
//     each plan (sorted newest first by `endedAt`).
//   - Optionally drops reports older than `maxAgeDays` days, but
//     never drops the most-recent-per-plan even if that report is
//     older than the age limit.
//
//  The policy is pure and Sendable. The persistence layer uses it
//  to compute identifiers to delete; SwiftData mutations stay
//  isolated to `AutonomousLoopPersistence.applyRetention`.
//

import Foundation

struct AutonomyLoopReportRetentionPolicy: Sendable, Hashable, Codable {
    var maxReportsPerPlan: Int
    /// `nil` means "no age limit". The UI stores `0` in @AppStorage
    /// to represent the disabled state; the `clamped(...)` factory
    /// normalises that into `nil`.
    var maxAgeDays: Int?

    // MARK: Defaults

    static let defaultMaxReportsPerPlan = 20
    /// Stored as `0` in @AppStorage to mean "disabled".
    static let defaultMaxAgeDaysStorageValue = 0

    // MARK: Safety bounds

    static let minMaxReportsPerPlan = 1
    static let maxMaxReportsPerPlan = 200
    static let minMaxAgeDaysStorageValue = 0
    static let maxMaxAgeDaysStorageValue = 365

    static let `default` = AutonomyLoopReportRetentionPolicy(
        maxReportsPerPlan: defaultMaxReportsPerPlan,
        maxAgeDays: nil
    )

    /// Build a policy from raw @AppStorage values, clamping each
    /// field to its safety bounds. `maxAgeDaysOrZero == 0` means
    /// "no age limit" and lands as `maxAgeDays = nil`.
    static func clamped(
        maxReportsPerPlan: Int,
        maxAgeDaysOrZero: Int
    ) -> AutonomyLoopReportRetentionPolicy {
        let cap = clamp(
            maxReportsPerPlan,
            lo: minMaxReportsPerPlan,
            hi: maxMaxReportsPerPlan
        )
        let ageOrZero = clamp(
            maxAgeDaysOrZero,
            lo: minMaxAgeDaysStorageValue,
            hi: maxMaxAgeDaysStorageValue
        )
        return AutonomyLoopReportRetentionPolicy(
            maxReportsPerPlan: cap,
            maxAgeDays: ageOrZero == 0 ? nil : ageOrZero
        )
    }

    /// Compute the identifiers of reports that should be deleted
    /// under this policy. The function is pure: it does not touch
    /// SwiftData or the filesystem.
    static func prune(
        reports: [AutonomousLoopReportRecord],
        policy: AutonomyLoopReportRetentionPolicy,
        now: Date = Date()
    ) -> [String] {
        let grouped = Dictionary(grouping: reports, by: \.planID)
        var toDelete: [String] = []
        for (_, planReports) in grouped {
            let sorted = planReports.sorted { $0.endedAt > $1.endedAt }
            for (index, report) in sorted.enumerated() {
                // Always preserve the most recent report per plan.
                if index == 0 { continue }
                if index >= policy.maxReportsPerPlan {
                    toDelete.append(report.identifier)
                    continue
                }
                if let maxAge = policy.maxAgeDays {
                    let ageSeconds = now.timeIntervalSince(report.endedAt)
                    if ageSeconds > Double(maxAge) * 86_400 {
                        toDelete.append(report.identifier)
                    }
                }
            }
        }
        return toDelete
    }

    /// Human-readable summary used by the safety panel.
    var summary: String {
        let age = maxAgeDays.map { "≤\($0)d" } ?? "no age limit"
        return "≤\(maxReportsPerPlan)/plan · \(age)"
    }

    private static func clamp(_ value: Int, lo: Int, hi: Int) -> Int {
        Swift.max(lo, Swift.min(hi, value))
    }
}
