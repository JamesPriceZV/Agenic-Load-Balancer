//
//  Agenic_Load_BalancerTests.swift
//  Agenic Load-BalancerTests
//
//  Created by Zinco Verde on 5/5/26.
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@Suite("Agenic Load-Balancer MVP")
struct Agenic_Load_BalancerTests {
    @Test func providerCatalogSeedsCoreProviders() {
        let providerIDs = Set(ProviderCatalog.defaultProfiles.map(\.identifier))

        #expect(providerIDs.contains("openai.codex"))
        #expect(providerIDs.contains("anthropic.claude-code"))
        #expect(providerIDs.contains("github.copilot-cli"))
        #expect(providerIDs.contains("xcodebuildmcp.source"))
        #expect(providerIDs.contains("deepseek.api"))
    }

    @Test func xctestLaunchesUseVolatileStore() {
        #expect(
            AgenicLaunchEnvironment.usesVolatileStore(
                arguments: ["/Applications/Agenic Load-Balancer.app"],
                environment: ["XCTestConfigurationFilePath": "/tmp/session.xctestconfiguration"]
            )
        )
        #expect(
            AgenicLaunchEnvironment.usesVolatileStore(
                arguments: ["Agenic Load-Balancer", "--uitesting"],
                environment: [:]
            )
        )
        #expect(
            !AgenicLaunchEnvironment.usesVolatileStore(
                arguments: ["/Applications/Agenic Load-Balancer.app"],
                environment: [:]
            )
        )
    }

    @MainActor
    @Test func swiftDataSchemaCreatesInMemoryRepository() throws {
        let schema = AgenicDataModel.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let project = AgentProject(name: "Demo Workspace", rootPath: "/tmp/demo")
        let provider = AgentProviderProfile(draft: ProviderCatalog.defaultProfiles[0])

        context.insert(project)
        context.insert(provider)
        try context.save()

        let projects = try context.fetch(FetchDescriptor<AgentProject>())
        let providers = try context.fetch(FetchDescriptor<AgentProviderProfile>())

        #expect(projects.count == 1)
        #expect(providers.count == 1)
    }

    @MainActor
    @Test func routingPrefersAvailableAuthenticatedProvider() async throws {
        let codex = AgentProviderProfile(draft: ProviderCatalog.defaultProfiles[0])
        codex.installedState = ProviderAvailabilityState.available.rawValue
        codex.authState = ProviderAuthState.authenticated.rawValue

        let claude = AgentProviderProfile(draft: ProviderCatalog.defaultProfiles[1])
        claude.installedState = ProviderAvailabilityState.missing.rawValue
        claude.authState = ProviderAuthState.unknown.rawValue

        let scores = await RoutingEngine().rank(
            prompt: "Implement the dashboard heatmap and fix any failing Swift tests.",
            mode: .implementation,
            providers: [codex.snapshot(), claude.snapshot()],
            usage: [
                UsageSnapshot(
                    providerID: codex.identifier,
                    callsToday: 1,
                    tokenCountToday: 1_000,
                    estimatedCostToday: 0.02,
                    sessionSecondsToday: 180,
                    limitPressure: 0.1,
                    refreshDate: nil
                ),
            ],
            accuracy: [
                AccuracySnapshot(
                    providerID: codex.identifier,
                    totalRatedRuns: 4,
                    averageScore: 0.9,
                    correctCount: 3,
                    repairCount: 1,
                    failureCount: 0
                ),
            ],
            coordinationEvents: []
        )

        #expect(scores.first?.providerID == codex.identifier)
        #expect((scores.first?.totalScore ?? 0) > 0.75)
    }

    @MainActor
    @Test func routingWeightsRecentReliabilityTrend() async throws {
        let shaky = AgentProviderProfile(draft: ProviderCatalog.defaultProfiles[0])
        shaky.installedState = ProviderAvailabilityState.available.rawValue
        shaky.authState = ProviderAuthState.authenticated.rawValue

        let steady = AgentProviderProfile(draft: ProviderCatalog.defaultProfiles[1])
        steady.installedState = ProviderAvailabilityState.available.rawValue
        steady.authState = ProviderAuthState.authenticated.rawValue

        let scores = await RoutingEngine().rank(
            prompt: "Review and implement a routing telemetry fix.",
            mode: .implementation,
            providers: [shaky.snapshot(), steady.snapshot()],
            usage: [],
            accuracy: [
                AccuracySnapshot(providerID: shaky.identifier, totalRatedRuns: 3, averageScore: 0.8, correctCount: 2, repairCount: 1, failureCount: 0),
                AccuracySnapshot(providerID: steady.identifier, totalRatedRuns: 3, averageScore: 0.8, correctCount: 2, repairCount: 1, failureCount: 0),
            ],
            reliability: [
                ProviderReliabilitySnapshot(
                    providerID: shaky.identifier,
                    providerName: shaky.displayName,
                    recentRunCount: 6,
                    succeededRunCount: 2,
                    failedRunCount: 4,
                    cancelledRunCount: 0,
                    quotaLimitedRunCount: 2,
                    rateLimitedRunCount: 0,
                    contextLimitedRunCount: 1,
                    reliabilityScore: 0.32,
                    summary: "Recent failures and limit signals."
                ),
                ProviderReliabilitySnapshot(
                    providerID: steady.identifier,
                    providerName: steady.displayName,
                    recentRunCount: 6,
                    succeededRunCount: 6,
                    failedRunCount: 0,
                    cancelledRunCount: 0,
                    quotaLimitedRunCount: 0,
                    rateLimitedRunCount: 0,
                    contextLimitedRunCount: 0,
                    reliabilityScore: 0.96,
                    summary: "Stable recent runs."
                ),
            ],
            coordinationEvents: []
        )

        #expect(scores.first?.providerID == steady.identifier)
        #expect(scores.first?.rationale.contains("recent reliability") == true)
        #expect(scores.first?.reliabilityImpact.contains("recent reliability") == true)
    }

    @Test func agentNotesFileIsCreatedWithCoordinationRules() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgenicLoadBalancerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let event = CoordinationEventSnapshot(
            identifier: UUID().uuidString,
            projectID: nil,
            phase: "Phase 1",
            wave: "Routing",
            step: "Rank",
            assignee: "Codex",
            status: CoordinationStatus.claimed.rawValue,
            title: "Validate route ranking",
            detail: "Use routing scores before dispatch.",
            relatedRunID: nil,
            commitSHA: nil,
            conflictMarker: nil,
            createdAt: Date()
        )

        let result = try await ProjectCoordinationActor().ensureAgentNotes(
            projectName: "Demo",
            rootPath: rootURL.path,
            events: [event]
        )

        let contents = try String(contentsOf: result.fileURL, encoding: .utf8)
        #expect(result.created)
        #expect(contents.contains("Every agent must read this file before acting."))
        #expect(contents.contains("Validate route ranking"))
    }
}
