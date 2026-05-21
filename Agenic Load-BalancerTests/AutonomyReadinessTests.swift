//
//  AutonomyReadinessTests.swift
//  Agenic Load-BalancerTests
//
//  Readiness scoring for safe autonomous work.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@MainActor
@Suite("Autonomy readiness")
struct AutonomyReadinessTests {
    @Test func readyWorkspaceScoresOneHundred() {
        let project = AgentProject(name: "Agenic", rootPath: "/repo")
        let provider = Self.readyProvider()
        let task = AutonomyTaskRecord(
            goalID: "goal-1",
            title: "Validate",
            detail: "Run tests",
            status: CoordinationStatus.planned.rawValue,
            mode: AgentExecutionMode.testBuild.rawValue,
            validationCommand: "xcodebuild test"
        )
        let health = MachineSyncCoordinator().health(
            machineID: "mac-a",
            displayName: "Mac A",
            lastSeenAt: Date(timeIntervalSince1970: 900),
            now: Date(timeIntervalSince1970: 1_000)
        )

        let snapshot = AutonomyReadinessBuilder().build(
            project: project,
            providers: [provider],
            policy: .defaultSafe,
            machineHealth: health,
            tasks: [task],
            validationGates: []
        )

        #expect(snapshot.state == AutonomyReadinessState.ready)
        #expect(snapshot.score == 100)
        #expect(snapshot.canPrepareAutonomousRuns)
        #expect(snapshot.activeTaskCount == 1)
    }

    @Test func missingWorkspaceBlocksAutonomy() {
        let health = MachineSyncCoordinator().health(
            machineID: "mac-a",
            displayName: "Mac A",
            lastSeenAt: Date(timeIntervalSince1970: 900),
            now: Date(timeIntervalSince1970: 1_000)
        )

        let snapshot = AutonomyReadinessBuilder().build(
            project: nil,
            providers: [Self.readyProvider()],
            policy: .defaultSafe,
            machineHealth: health,
            tasks: [],
            validationGates: []
        )

        #expect(snapshot.state == AutonomyReadinessState.blocked)
        #expect(!snapshot.canPrepareAutonomousRuns)
        #expect(snapshot.nextAction == "Resolve workspace.")
    }

    @Test func failedValidationGateBlocksNextRun() {
        let project = AgentProject(name: "Agenic", rootPath: "/repo")
        let gate = ValidationGateRecord(
            taskID: "task-1",
            command: "xcodebuild test",
            status: "failed",
            outputExcerpt: "Tests failed"
        )
        let health = MachineSyncCoordinator().health(
            machineID: "mac-a",
            displayName: "Mac A",
            lastSeenAt: Date(timeIntervalSince1970: 900),
            now: Date(timeIntervalSince1970: 1_000)
        )

        let snapshot = AutonomyReadinessBuilder().build(
            project: project,
            providers: [Self.readyProvider()],
            policy: .defaultSafe,
            machineHealth: health,
            tasks: [],
            validationGates: [gate]
        )

        #expect(snapshot.state == AutonomyReadinessState.blocked)
        #expect(snapshot.blockedTaskCount == 0)
        #expect(snapshot.validationGateCount == 1)
        #expect(snapshot.nextAction == "Resolve validation.")
    }

    private static func readyProvider() -> AgentProviderProfile {
        let draft = AgentProviderDraft(
            identifier: "codex.cli",
            displayName: "Codex CLI",
            providerFamily: "OpenAI",
            homepageURL: "https://developers.openai.com/codex",
            sourceURL: "https://developers.openai.com/codex/cli",
            binaryName: "codex",
            installCommand: "",
            verificationCommand: "codex --version",
            authGuide: "codex login",
            authMethods: ProviderAuthState.authenticated.rawValue,
            capabilities: "code-editing",
            supportedExecutionModes: AgentExecutionMode.allCases.map(\.rawValue).joined(separator: ","),
            modelListSource: "local",
            costPolicySummary: "subscription",
            quotaPolicySummary: "account",
            safetyNotes: "approval gated"
        )
        let provider = AgentProviderProfile(draft: draft)
        provider.installedState = ProviderAvailabilityState.available.rawValue
        provider.authState = ProviderAuthState.authenticated.rawValue
        provider.isEnabled = true
        return provider
    }
}
