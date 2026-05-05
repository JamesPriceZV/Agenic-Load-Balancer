//
//  SnapshotPipelineTests.swift
//  Agenic Load-BalancerTests
//
//  Created by Claude on 5/5/26.
//
//  Phase 3: tests for the snapshot archive + restore pipeline. These
//  exercise round-trip encoding, build/preview, diff computation, replace
//  and merge apply paths, and corrupted-archive detection — all against
//  in-memory `ModelContainer`s so no real iCloud or filesystem mutations
//  occur.
//

import Foundation
import SwiftData
import Testing
@testable import Agenic_Load_Balancer

@MainActor
@Suite("Snapshot pipeline")
struct SnapshotPipelineTests {
    // MARK: Helpers

    private static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "SnapshotPipelineTests-\(UUID().uuidString)",
            schema: AgenicDataModel.schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: AgenicDataModel.schema, configurations: [configuration])
    }

    /// Seed a context with a representative mix of records across every
    /// model so totals and round-trip tests have meaningful counts.
    private static func seed(_ context: ModelContext, projectName: String = "Demo") throws {
        let project = AgentProject(name: projectName, rootPath: "/tmp/\(projectName)")
        let provider = AgentProviderProfile(draft: ProviderCatalog.defaultProfiles[0])
        let secondProvider = AgentProviderProfile(draft: ProviderCatalog.defaultProfiles[1])
        let setup = ProviderSetupRecord(providerID: provider.identifier, setupStage: "auth")
        let thread = PromptThreadRecord(projectID: project.identifier, title: "Implement heatmap")
        let message = PromptMessageRecord(threadID: thread.identifier, role: "user", contentExcerpt: "Implement…")
        let usage = UsageLedgerEntry(providerID: provider.identifier, runID: UUID().uuidString, promptTokens: 120, completionTokens: 80)
        let decision = RoutingDecisionRecord(
            promptThreadID: thread.identifier,
            selectedProviderID: provider.identifier,
            selectedMode: AgentExecutionMode.implementation.rawValue,
            scoreSummary: "test"
        )
        let outcome = RunOutcomeRecord(providerID: provider.identifier, projectID: project.identifier)
        let event = CoordinationEventRecord(projectID: project.identifier, title: "Active step")
        let snapshot = CloudSnapshotRecord(scope: "test", recordCounts: "n=1", checksum: "abc")
        let keychain = KeychainReferenceRecord(providerID: provider.identifier, serviceName: "svc", accountName: "acct", purpose: "auth")

        context.insert(project)
        context.insert(provider)
        context.insert(secondProvider)
        context.insert(setup)
        context.insert(thread)
        context.insert(message)
        context.insert(usage)
        context.insert(decision)
        context.insert(outcome)
        context.insert(event)
        context.insert(snapshot)
        context.insert(keychain)
        try context.save()
    }

    // MARK: Tests

    @Test func roundTripEncodeDecodePreservesChecksum() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        try Self.seed(context, projectName: "RoundTrip")

        let payload = try SnapshotPipeline.buildPayload(from: context, appVersion: "1.0")
        let data = try SnapshotArchiveCodec.encode(payload)
        let decoded = try SnapshotArchiveCodec.decode(data)

        #expect(decoded.checksum == payload.checksum)
        #expect(decoded.body.totalRecords == payload.body.totalRecords)
        #expect(decoded.body.projects.first?.name == "RoundTrip")
        try SnapshotArchiveCodec.verify(decoded)
    }

    @Test func buildPayloadCapturesCountsForEveryModel() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        try Self.seed(context)

        let payload = try SnapshotPipeline.buildPayload(from: context, appVersion: "1.0")
        let counts = payload.body.countsByModel

        #expect(counts[ModelKey.project] == 1)
        #expect(counts[ModelKey.providerProfile] == 2)
        #expect(counts[ModelKey.providerSetup] == 1)
        #expect(counts[ModelKey.promptThread] == 1)
        #expect(counts[ModelKey.promptMessage] == 1)
        #expect(counts[ModelKey.usageLedger] == 1)
        #expect(counts[ModelKey.routingDecision] == 1)
        #expect(counts[ModelKey.runOutcome] == 1)
        #expect(counts[ModelKey.coordination] == 1)
        #expect(counts[ModelKey.cloudSnapshot] == 1)
        #expect(counts[ModelKey.keychainReference] == 1)
    }

    @Test func loadPreviewProducesSeparateContainer() throws {
        let liveContainer = try Self.makeContainer()
        let liveContext = ModelContext(liveContainer)
        try Self.seed(liveContext, projectName: "Live")

        let payload = try SnapshotPipeline.buildPayload(from: liveContext, appVersion: "1.0")
        let previewContainer = try SnapshotPipeline.loadPreview(payload: payload)
        let previewContext = ModelContext(previewContainer)

        let previewProjects = try previewContext.fetch(FetchDescriptor<AgentProject>())
        #expect(previewProjects.first?.name == "Live")

        // Mutating the preview container must not change the live one.
        if let preview = previewProjects.first {
            preview.name = "Mutated"
            try previewContext.save()
        }
        let liveProjects = try liveContext.fetch(FetchDescriptor<AgentProject>())
        #expect(liveProjects.first?.name == "Live")
    }

    @Test func computeDiffSplitsArchiveOnlyAndOverlappingRecords() throws {
        let archiveContainer = try Self.makeContainer()
        let archiveContext = ModelContext(archiveContainer)
        try Self.seed(archiveContext, projectName: "Archive")
        let payload = try SnapshotPipeline.buildPayload(from: archiveContext, appVersion: "1.0")

        let liveContainer = try Self.makeContainer()
        let liveContext = ModelContext(liveContainer)

        // Manually re-insert the same project (same identifier) into the live
        // store so we have a guaranteed overlap. We grab the identifier from
        // the archive payload to mirror what the merge path would observe.
        let archiveProject = try #require(payload.body.projects.first)
        liveContext.insert(archiveProject.makeRecord())

        // Add an extra project that exists only in live.
        liveContext.insert(AgentProject(name: "OnlyLive"))
        try liveContext.save()

        let diff = try SnapshotPipeline.computeDiff(archive: payload, against: liveContext)

        #expect(diff.overlapCounts[ModelKey.project] == 1)
        #expect(diff.archiveOnlyCounts[ModelKey.project] == 0)
        #expect(diff.liveOnlyCounts[ModelKey.project] == 1)
        // Archive only has providers/etc. that the live container lacks.
        #expect(diff.archiveOnlyCounts[ModelKey.providerProfile] == 2)
    }

    @Test func applyReplaceDeletesLiveAndReinsertsArchive() throws {
        let archiveContainer = try Self.makeContainer()
        let archiveContext = ModelContext(archiveContainer)
        try Self.seed(archiveContext, projectName: "Archive")
        let payload = try SnapshotPipeline.buildPayload(from: archiveContext, appVersion: "1.0")

        let liveContainer = try Self.makeContainer()
        let liveContext = ModelContext(liveContainer)
        liveContext.insert(AgentProject(name: "WillBeDeleted"))
        liveContext.insert(AgentProject(name: "AlsoDeleted"))
        try liveContext.save()
        #expect(try liveContext.fetch(FetchDescriptor<AgentProject>()).count == 2)

        try SnapshotPipeline.applyReplace(payload: payload, into: liveContext)

        let projects = try liveContext.fetch(FetchDescriptor<AgentProject>())
        #expect(projects.count == 1)
        #expect(projects.first?.name == "Archive")
        let providers = try liveContext.fetch(FetchDescriptor<AgentProviderProfile>())
        #expect(providers.count == 2)
    }

    @Test func applyMergeSkipsOverlappingIdentifiers() throws {
        let archiveContainer = try Self.makeContainer()
        let archiveContext = ModelContext(archiveContainer)
        try Self.seed(archiveContext, projectName: "Archive")
        let payload = try SnapshotPipeline.buildPayload(from: archiveContext, appVersion: "1.0")

        // Live store starts with the same project identifier as the archive
        // (so it should be skipped) plus one extra project that the archive
        // does not contain.
        let liveContainer = try Self.makeContainer()
        let liveContext = ModelContext(liveContainer)
        let archiveProject = try #require(payload.body.projects.first)
        liveContext.insert(archiveProject.makeRecord())
        liveContext.insert(AgentProject(name: "OnlyLive"))
        try liveContext.save()

        let result = try SnapshotPipeline.applyMerge(payload: payload, into: liveContext)

        #expect(result.skipped == 1) // the duplicate project
        #expect(result.inserted == payload.body.totalRecords - 1)

        let projects = try liveContext.fetch(FetchDescriptor<AgentProject>())
        #expect(projects.count == 2) // archive + OnlyLive
    }

    @Test func corruptedChecksumIsRejected() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        try Self.seed(context)

        let payload = try SnapshotPipeline.buildPayload(from: context, appVersion: "1.0")
        // Tamper: build a new payload with the original body but a bad checksum.
        let tampered = SnapshotPayload(
            version: payload.version,
            createdAt: payload.createdAt,
            appVersion: payload.appVersion,
            checksum: "deadbeef",
            body: payload.body
        )

        do {
            try SnapshotArchiveCodec.verify(tampered)
            Issue.record("Checksum verification should have thrown.")
        } catch let error as SnapshotArchiveError {
            switch error {
            case .checksumMismatch:
                break // expected
            default:
                Issue.record("Expected .checksumMismatch, got \(error)")
            }
        }
    }

    @Test func unsupportedVersionIsRejected() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        try Self.seed(context)

        let payload = try SnapshotPipeline.buildPayload(from: context, appVersion: "1.0")
        let bumped = SnapshotPayload(
            version: "999.0",
            createdAt: payload.createdAt,
            appVersion: payload.appVersion,
            checksum: payload.checksum,
            body: payload.body
        )

        do {
            try SnapshotArchiveCodec.verify(bumped)
            Issue.record("Unsupported version should have thrown.")
        } catch let error as SnapshotArchiveError {
            switch error {
            case .unsupportedVersion(let v):
                #expect(v == "999.0")
            default:
                Issue.record("Expected .unsupportedVersion, got \(error)")
            }
        }
    }
}
