//
//  AutonomyLoopBudgetConfig.swift
//  Agenic Load-Balancer
//
//  Sprint Q.8: user-configurable scheduler budget caps with safe
//  clamping. Sits between `@AppStorage` (which lets the Autonomy
//  control room expose steppers for each cap) and `AutonomousLoopBudget`
//  (which the scheduler consumes).
//

import Foundation

struct AutonomyLoopBudgetConfig: Sendable, Hashable, Codable {
    var maxIterations: Int
    var maxValidationFailures: Int
    var maxApprovalsBeforeHalt: Int

    /// Defaults match `AutonomousLoopBudget.default` so existing
    /// callers that haven't migrated still see identical behaviour.
    static let defaultMaxIterations = 12
    static let defaultMaxValidationFailures = 1
    static let defaultMaxApprovalsBeforeHalt = 1

    /// Safety bounds. The autonomy contract is intentionally
    /// conservative — a misconfigured budget can amplify a runaway
    /// plan, so we clamp at the UI layer instead of trusting raw
    /// `@AppStorage` writes.
    static let minMaxIterations = 1
    static let maxMaxIterations = 50
    static let minMaxValidationFailures = 1
    static let maxMaxValidationFailures = 10
    static let minMaxApprovalsBeforeHalt = 1
    static let maxMaxApprovalsBeforeHalt = 10

    static let `default` = AutonomyLoopBudgetConfig(
        maxIterations: defaultMaxIterations,
        maxValidationFailures: defaultMaxValidationFailures,
        maxApprovalsBeforeHalt: defaultMaxApprovalsBeforeHalt
    )

    /// Clamp every cap to its configured min/max. Out-of-range
    /// inputs land at the nearest boundary, never throw.
    static func clamped(
        maxIterations: Int,
        maxValidationFailures: Int,
        maxApprovalsBeforeHalt: Int
    ) -> AutonomyLoopBudgetConfig {
        AutonomyLoopBudgetConfig(
            maxIterations: clamp(
                maxIterations,
                lo: minMaxIterations,
                hi: maxMaxIterations
            ),
            maxValidationFailures: clamp(
                maxValidationFailures,
                lo: minMaxValidationFailures,
                hi: maxMaxValidationFailures
            ),
            maxApprovalsBeforeHalt: clamp(
                maxApprovalsBeforeHalt,
                lo: minMaxApprovalsBeforeHalt,
                hi: maxMaxApprovalsBeforeHalt
            )
        )
    }

    /// Convert to the runtime budget consumed by the scheduler.
    var asBudget: AutonomousLoopBudget {
        AutonomousLoopBudget(
            maxIterations: maxIterations,
            maxValidationFailures: maxValidationFailures,
            maxApprovalsBeforeHalt: maxApprovalsBeforeHalt
        )
    }

    /// Human-readable summary used by the budget panel in the
    /// Autonomy control room.
    var summary: String {
        "≤\(maxIterations) iter · ≤\(maxValidationFailures) fail · ≤\(maxApprovalsBeforeHalt) approval"
    }

    private static func clamp(_ value: Int, lo: Int, hi: Int) -> Int {
        Swift.max(lo, Swift.min(hi, value))
    }
}
