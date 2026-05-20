//
//  ValidationGateRunnerTests.swift
//  Agenic Load-BalancerTests
//
//  Phase 7.6 validation gate tests.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Phase 7.6 validation gates")
struct ValidationGateRunnerTests {
    @Test func passedReflectsZeroExitCode() {
        let result = ValidationGateResult(
            command: "xcodebuild test",
            exitCode: 0,
            outputExcerpt: "** TEST SUCCEEDED **",
            startedAt: Date(),
            endedAt: Date()
        )

        #expect(result.passed)
    }

    @Test func scriptedRunnerReturnsConfiguredResult() async {
        let expected = ValidationGateResult(
            command: "swift test",
            exitCode: 1,
            outputExcerpt: "failed",
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2)
        )

        let result = await ScriptedValidationGateRunner(result: expected).run(
            command: "ignored",
            workingDirectory: "/repo"
        )

        #expect(result == expected)
        #expect(!result.passed)
    }
}
