//
//  AutonomyLoopBudgetConfigTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint Q.8: clamp out-of-range autonomy budget caps before they
//  reach the scheduler.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Sprint Q.8 autonomy loop budget config")
struct AutonomyLoopBudgetConfigTests {
    @Test func defaultsMatchAutonomousLoopBudgetDefault() {
        let config = AutonomyLoopBudgetConfig.default
        #expect(config.maxIterations == AutonomousLoopBudget.default.maxIterations)
        #expect(config.maxValidationFailures == AutonomousLoopBudget.default.maxValidationFailures)
        #expect(config.maxApprovalsBeforeHalt == AutonomousLoopBudget.default.maxApprovalsBeforeHalt)
    }

    @Test func clampedReturnsInputWhenInsideRange() {
        let config = AutonomyLoopBudgetConfig.clamped(
            maxIterations: 8,
            maxValidationFailures: 3,
            maxApprovalsBeforeHalt: 2
        )
        #expect(config.maxIterations == 8)
        #expect(config.maxValidationFailures == 3)
        #expect(config.maxApprovalsBeforeHalt == 2)
    }

    @Test func clampedRaisesValuesBelowMinimum() {
        let config = AutonomyLoopBudgetConfig.clamped(
            maxIterations: -5,
            maxValidationFailures: 0,
            maxApprovalsBeforeHalt: -10
        )
        #expect(config.maxIterations == AutonomyLoopBudgetConfig.minMaxIterations)
        #expect(config.maxValidationFailures == AutonomyLoopBudgetConfig.minMaxValidationFailures)
        #expect(config.maxApprovalsBeforeHalt == AutonomyLoopBudgetConfig.minMaxApprovalsBeforeHalt)
    }

    @Test func clampedLowersValuesAboveMaximum() {
        let config = AutonomyLoopBudgetConfig.clamped(
            maxIterations: 1_000,
            maxValidationFailures: 99,
            maxApprovalsBeforeHalt: 999
        )
        #expect(config.maxIterations == AutonomyLoopBudgetConfig.maxMaxIterations)
        #expect(config.maxValidationFailures == AutonomyLoopBudgetConfig.maxMaxValidationFailures)
        #expect(config.maxApprovalsBeforeHalt == AutonomyLoopBudgetConfig.maxMaxApprovalsBeforeHalt)
    }

    @Test func asBudgetProducesMatchingLoopBudget() {
        let config = AutonomyLoopBudgetConfig.clamped(
            maxIterations: 10,
            maxValidationFailures: 2,
            maxApprovalsBeforeHalt: 3
        )
        let budget = config.asBudget
        #expect(budget.maxIterations == 10)
        #expect(budget.maxValidationFailures == 2)
        #expect(budget.maxApprovalsBeforeHalt == 3)
    }

    @Test func summaryIncludesAllThreeCaps() {
        let summary = AutonomyLoopBudgetConfig.clamped(
            maxIterations: 4,
            maxValidationFailures: 2,
            maxApprovalsBeforeHalt: 1
        ).summary
        #expect(summary.contains("4"))
        #expect(summary.contains("2"))
        #expect(summary.contains("1"))
        #expect(summary.contains("iter"))
        #expect(summary.contains("fail"))
        #expect(summary.contains("approval"))
    }
}
