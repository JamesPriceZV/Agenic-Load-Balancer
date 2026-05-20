//
//  CoordinationAndSync.swift
//  Agenic Load-Balancer
//
//  Created by OpenAI Codex on 5/5/26.
//

import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftData

enum AppServices {
    static let routingEngine = RoutingEngine()
    static let routingRecommendation = RoutingRecommendationCoordinator()
    static let autonomyManager = AutonomousProjectManager()
    static let healthMonitor = ProviderHealthMonitor()
    static let processRunner = AgentProcessRunner()
    static let coordination = ProjectCoordinationActor()
    static let cloudSync = CloudSyncCoordinator()
    static let restore = SnapshotRestoreCoordinator()
    static let setupWizard = ProviderSetupWizard()
    static let gitCheckpoint: GitCheckpointing = GitCheckpointCoordinator()
}

@MainActor
enum AppBootstrapper {
    static func ensureSeedData(in context: ModelContext) {
        do {
            let providers = try context.fetch(FetchDescriptor<AgentProviderProfile>())
            if providers.isEmpty {
                for draft in ProviderCatalog.defaultProfiles {
                    context.insert(AgentProviderProfile(draft: draft))
                    context.insert(ProviderSetupRecord(providerID: draft.identifier))
                }
            }

            let events = try context.fetch(FetchDescriptor<CoordinationEventRecord>())
            if events.isEmpty {
                context.insert(
                    CoordinationEventRecord(
                        phase: "Phase 0",
                        wave: "Wave 0",
                        step: "Step 0",
                        status: CoordinationStatus.checkpointed.rawValue,
                        title: "MVP orchestration plan seeded",
                        detail: "SwiftData is the app repository, CloudKit sync is configured for backup, and AgentNotes.md is the project coordination artifact."
                    )
                )
            }

            try context.save()
        } catch {
            assertionFailure("Seed data failed: \(error.localizedDescription)")
        }
    }
}

struct AgentNotesResult: Sendable {
    let fileURL: URL
    let created: Bool
    let conflictDetected: Bool
}

/// Result of reconciling the on-disk `AgentNotes.md` against the SwiftData
/// coordination ledger. Surfaced to the UI so users can choose to keep the
/// existing file, regenerate from SwiftData, or hand-resolve a conflict.
struct AgentNotesReconciliation: Sendable {
    enum State: Sendable, Hashable {
        case fileMissing
        case fileMatches
        case fileDiverged(localChecksum: String, generatedChecksum: String)
        case conflictMarkers(detail: String)
    }

    let fileURL: URL
    let state: State
    let suggestedContent: String
    let onDiskContent: String?

    var requiresAttention: Bool {
        switch state {
        case .fileMatches: return false
        case .fileMissing, .fileDiverged, .conflictMarkers: return true
        }
    }
}

@MainActor
enum CoordinationEventMaintenance {
    static func staleDispatchEvents(
        in events: [CoordinationEventRecord],
        projectID: String
    ) -> [CoordinationEventRecord] {
        events.filter { event in
            (event.projectID == projectID || event.projectID == nil) &&
                event.phase == "Phase 2" &&
                event.wave == "Dispatch" &&
                (event.status == CoordinationStatus.blocked.rawValue ||
                    event.status == CoordinationStatus.cancelled.rawValue) &&
                isStaleDispatchRecord(event.snapshot())
        }
    }

    static func isStaleDispatchRecord(_ event: CoordinationEventSnapshot) -> Bool {
        guard event.phase == "Phase 2", event.wave == "Dispatch" else { return false }
        if event.detail.contains("Resolved stale dispatch record") { return false }
        if event.status == CoordinationStatus.cancelled.rawValue { return true }
        guard event.status == CoordinationStatus.blocked.rawValue else { return false }
        let text = [
            event.title,
            event.detail,
            event.conflictMarker ?? "",
        ].joined(separator: "\n").localizedLowercase
        return text.contains("cancelled") || text.contains("canceled")
    }

    static func resolveStaleDispatchEvents(
        _ events: [CoordinationEventRecord],
        resolvedAt: Date = Date()
    ) -> Int {
        var resolved = 0
        for event in events where isStaleDispatchRecord(event.snapshot()) {
            resolved += 1
            if event.status != CoordinationStatus.cancelled.rawValue {
                event.status = CoordinationStatus.cancelled.rawValue
            }
            if let marker = event.conflictMarker,
               marker.localizedCaseInsensitiveContains("cancel") {
                event.conflictMarker = nil
            }
            if !event.detail.contains("Resolved stale dispatch record") {
                event.detail += "\nResolved stale dispatch record on \(resolvedAt.formatted(date: .abbreviated, time: .standard))."
            }
        }
        return resolved
    }
}

actor ProjectCoordinationActor {
    private let fileManager: FileManager = .default

    func ensureAgentNotes(
        projectName: String,
        rootPath: String,
        events: [CoordinationEventSnapshot]
    ) throws -> AgentNotesResult {
        let fileURL = agentNotesURL(rootPath: rootPath)

        guard fileManager.fileExists(atPath: rootPath) else {
            throw CoordinationError.missingProjectRoot(rootPath)
        }

        if fileManager.fileExists(atPath: fileURL.path) {
            let text = try coordinatedReadString(at: fileURL)
            let conflictDetected = Self.hasConflictMarkers(in: text)
            return AgentNotesResult(fileURL: fileURL, created: false, conflictDetected: conflictDetected)
        }

        let content = renderAgentNotes(projectName: projectName, events: events)
        try coordinatedWriteString(content, to: fileURL)
        return AgentNotesResult(fileURL: fileURL, created: true, conflictDetected: false)
    }

    func append(
        event: CoordinationEventSnapshot,
        projectName: String,
        rootPath: String
    ) throws -> AgentNotesResult {
        let fileURL = agentNotesURL(rootPath: rootPath)
        let existedBeforeWrite = fileManager.fileExists(atPath: fileURL.path)
        let existing: String
        if existedBeforeWrite {
            existing = (try? coordinatedReadString(at: fileURL)) ?? renderAgentNotes(projectName: projectName, events: [])
        } else {
            existing = renderAgentNotes(projectName: projectName, events: [])
        }
        let conflictDetected = Self.hasConflictMarkers(in: existing)
        let appended = existing + "\n" + renderEvent(event)
        try coordinatedWriteString(appended, to: fileURL)
        return AgentNotesResult(fileURL: fileURL, created: !existedBeforeWrite, conflictDetected: conflictDetected)
    }

    /// Compare the on-disk file against a freshly generated version from the
    /// SwiftData coordination ledger. Lets the UI offer "regenerate from
    /// SwiftData" without silently overwriting hand-edits.
    func reconcile(
        projectName: String,
        rootPath: String,
        events: [CoordinationEventSnapshot]
    ) throws -> AgentNotesReconciliation {
        let fileURL = agentNotesURL(rootPath: rootPath)
        guard fileManager.fileExists(atPath: rootPath) else {
            throw CoordinationError.missingProjectRoot(rootPath)
        }
        let suggested = renderAgentNotes(projectName: projectName, events: events)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return AgentNotesReconciliation(
                fileURL: fileURL,
                state: .fileMissing,
                suggestedContent: suggested,
                onDiskContent: nil
            )
        }

        let existing = (try? coordinatedReadString(at: fileURL)) ?? ""
        if Self.hasConflictMarkers(in: existing) {
            return AgentNotesReconciliation(
                fileURL: fileURL,
                state: .conflictMarkers(detail: "On-disk AgentNotes.md contains conflict markers — resolve manually before regenerating."),
                suggestedContent: suggested,
                onDiskContent: existing
            )
        }

        let normalisedExisting = Self.normalisedForCompare(existing)
        let normalisedSuggested = Self.normalisedForCompare(suggested)
        if normalisedExisting == normalisedSuggested {
            return AgentNotesReconciliation(
                fileURL: fileURL,
                state: .fileMatches,
                suggestedContent: suggested,
                onDiskContent: existing
            )
        }
        return AgentNotesReconciliation(
            fileURL: fileURL,
            state: .fileDiverged(
                localChecksum: Self.checksum(of: existing),
                generatedChecksum: Self.checksum(of: suggested)
            ),
            suggestedContent: suggested,
            onDiskContent: existing
        )
    }

    /// Regenerate the file from `suggestedContent`. Caller is expected to
    /// have shown the user a diff first; this method does NOT preserve
    /// existing content.
    func applyReconciliation(rootPath: String, suggestedContent: String) throws -> AgentNotesResult {
        let fileURL = agentNotesURL(rootPath: rootPath)
        let existed = fileManager.fileExists(atPath: fileURL.path)
        try coordinatedWriteString(suggestedContent, to: fileURL)
        return AgentNotesResult(fileURL: fileURL, created: !existed, conflictDetected: false)
    }

    /// Read up to `maxBytes` of the on-disk AgentNotes content for use as a
    /// preflight excerpt when dispatching an agent. Returns `nil` when the
    /// file is absent so callers can degrade gracefully.
    func readAgentNotesExcerpt(rootPath: String, maxBytes: Int = 4_000) -> String? {
        let fileURL = agentNotesURL(rootPath: rootPath)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        guard let text = try? coordinatedReadString(at: fileURL) else { return nil }
        if text.count <= maxBytes { return text }
        let prefix = String(text.prefix(maxBytes))
        return prefix + "\n…[truncated for preflight]"
    }

    /// Read the full on-disk AgentNotes content for prompt-relevant AI
    /// summarisation. Callers decide how much of this to display or inject.
    func readAgentNotes(rootPath: String) -> String? {
        let fileURL = agentNotesURL(rootPath: rootPath)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try? coordinatedReadString(at: fileURL)
    }

    func renderAgentNotes(projectName: String, events: [CoordinationEventSnapshot]) -> String {
        let sortedEvents = events.sorted { $0.createdAt < $1.createdAt }
        let activeEvents = sortedEvents
            .filter { CoordinationStatus.isActiveForPreflight($0.status) }
            .map(renderEvent)
            .joined(separator: "\n")
        let historicalEvents = sortedEvents
            .filter { CoordinationStatus.isHistorical($0.status) }
            .map(renderEvent)
            .joined(separator: "\n")

        return """
        # AgentNotes.md

        Project: \(projectName)
        Created: \(Date().formatted(date: .abbreviated, time: .standard))

        ## Coordination Rules
        - Every agent must read this file before acting.
        - Summarize active constraints before edits.
        - Claim in-progress work and avoid conflicting tasks.
        - Record phases, waves, steps, handoffs, blockers, tests, commits, and push checkpoints.
        - SwiftData is the app's canonical repository; this file is the project-visible coordination view.

        ## Active Work
        \(activeEvents.isEmpty ? "- No active work recorded yet." : activeEvents)

        ## History
        \(historicalEvents.isEmpty ? "- No historical coordination events recorded yet." : historicalEvents)
        """
    }

    private func renderEvent(_ event: CoordinationEventSnapshot) -> String {
        """
        - [\(event.status)] \(event.phase) / \(event.wave) / \(event.step): \(event.title)
          Assignee: \(event.assignee)
          Created: \(event.createdAt.formatted(date: .abbreviated, time: .standard))
          Detail: \(event.detail.isEmpty ? "No detail recorded." : event.detail)
          Run: \(event.relatedRunID ?? "n/a")
          Commit: \(event.commitSHA ?? "n/a")
          Conflict: \(event.conflictMarker ?? "none")
        """
    }

    private func agentNotesURL(rootPath: String) -> URL {
        URL(fileURLWithPath: rootPath, isDirectory: true).appendingPathComponent("AgentNotes.md")
    }

    /// Coordinated read using NSFileCoordinator so concurrent agents writing
    /// the same file don't tear our read.
    private func coordinatedReadString(at url: URL) throws -> String {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var capturedError: Error?
        var contents: String = ""
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { resolved in
            do {
                contents = try String(contentsOf: resolved, encoding: .utf8)
            } catch {
                capturedError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let capturedError { throw capturedError }
        return contents
    }

    /// Coordinated atomic write using NSFileCoordinator. Falls back to
    /// surfacing the coordinator error so callers can react.
    private func coordinatedWriteString(_ contents: String, to url: URL) throws {
        guard let data = contents.data(using: .utf8) else {
            throw CoordinationError.encodingFailed
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var capturedError: Error?
        coordinator.coordinate(writingItemAt: url, options: [.forReplacing], error: &coordinatorError) { resolved in
            do {
                try data.write(to: resolved, options: [.atomic])
            } catch {
                capturedError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let capturedError { throw capturedError }
    }

    private static func hasConflictMarkers(in text: String) -> Bool {
        text.contains("<<<<<<<") || text.contains(">>>>>>>") || text.contains("CONFLICT")
    }

    /// Normalise away formatting differences (the rendered "Created:" line
    /// includes a wall-clock timestamp; ignore it for the equality check so
    /// we don't claim divergence on every rebuild).
    private static func normalisedForCompare(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                if line.hasPrefix("Created:") { return "Created:" }
                return line
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func checksum(of text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}

enum CoordinationError: Error, Sendable, LocalizedError {
    case missingProjectRoot(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingProjectRoot(let path): "Project root does not exist: \(path)"
        case .encodingFailed: "Could not encode AgentNotes content as UTF-8."
        }
    }
}

struct CloudSyncStatusSnapshot: Sendable {
    let containerIdentifier: String
    let lastLocalSave: Date?
    let lastCloudEvent: Date?
    let status: String
    let detail: String
}

actor CloudSyncCoordinator {
    private var status = CloudSyncStatusSnapshot(
        containerIdentifier: AgenicDataModel.cloudKitContainerIdentifier,
        lastLocalSave: nil,
        lastCloudEvent: nil,
        status: "configured",
        detail: "Private CloudKit sync is configured through SwiftData."
    )

    func currentStatus() -> CloudSyncStatusSnapshot {
        status
    }

    func recordLocalSave() {
        status = CloudSyncStatusSnapshot(
            containerIdentifier: status.containerIdentifier,
            lastLocalSave: Date(),
            lastCloudEvent: status.lastCloudEvent,
            status: "saving",
            detail: "SwiftData save recorded; CloudKit will sync according to system availability."
        )
    }

    func recordRemoteNotification() {
        status = CloudSyncStatusSnapshot(
            containerIdentifier: status.containerIdentifier,
            lastLocalSave: status.lastLocalSave,
            lastCloudEvent: Date(),
            status: "remoteUpdate",
            detail: "Remote CloudKit notification observed."
        )
    }
}

struct CloudSnapshotDraft: Sendable {
    let scope: String
    let recordCounts: String
    let checksum: String
    let restoreNotes: String
}

actor SnapshotRestoreCoordinator {
    private let archiveDirectoryName = "AgenicSnapshots"
    private let archiveFileSuffix = ".agenicarchive.json"

    /// URL of the directory where archive JSON files are stored. Created on
    /// first access so callers don't have to bootstrap state.
    func archiveDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = baseURL
            .appendingPathComponent("Agenic Load-Balancer", isDirectory: true)
            .appendingPathComponent(archiveDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Deterministic archive URL for a given snapshot identifier.
    func archiveURL(forIdentifier identifier: String) throws -> URL {
        try archiveDirectory().appendingPathComponent("\(identifier)\(archiveFileSuffix)", isDirectory: false)
    }

    /// Persist the encoded payload as an archive file keyed by identifier.
    func writeArchive(payload: SnapshotPayload, identifier: String) throws -> URL {
        let url = try archiveURL(forIdentifier: identifier)
        let data = try SnapshotArchiveCodec.encode(payload)
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            throw SnapshotArchiveError.fileWriteFailed(error.localizedDescription)
        }
    }

    /// Copy an archive file to a new location chosen by the user.
    func exportArchive(forIdentifier identifier: String, to destination: URL) throws -> URL {
        let source = try archiveURL(forIdentifier: identifier)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// Decode and verify a payload from a known on-disk archive identifier.
    func readArchive(forIdentifier identifier: String) throws -> SnapshotPayload {
        let url = try archiveURL(forIdentifier: identifier)
        return try readArchive(at: url)
    }

    /// Decode and verify a payload from any archive URL (e.g. user-imported).
    func readArchive(at url: URL) throws -> SnapshotPayload {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SnapshotArchiveError.fileReadFailed(error.localizedDescription)
        }
        let payload = try SnapshotArchiveCodec.decode(data)
        try SnapshotArchiveCodec.verify(payload)
        return payload
    }

    /// Remove an archive file. Silently no-ops if the file is missing.
    func deleteArchive(forIdentifier identifier: String) throws {
        let url = try archiveURL(forIdentifier: identifier)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Build a metadata draft summarising the snapshot. Uses the supplied
    /// checksum (typically the payload's body hash) when available, otherwise
    /// falls back to hashing the recordCounts string for backward
    /// compatibility with the Phase 0 placeholder behaviour.
    func buildSnapshot(
        projectCount: Int,
        providerCount: Int,
        runCount: Int,
        coordinationCount: Int,
        checksum: String? = nil
    ) -> CloudSnapshotDraft {
        let recordCounts = "projects=\(projectCount);providers=\(providerCount);runs=\(runCount);coordination=\(coordinationCount)"
        let resolvedChecksum: String = {
            if let checksum, !checksum.isEmpty { return checksum }
            return SHA256.hash(data: Data(recordCounts.utf8))
                .compactMap { String(format: "%02x", $0) }
                .joined()
        }()

        return CloudSnapshotDraft(
            scope: "SwiftData master repository",
            recordCounts: recordCounts,
            checksum: resolvedChecksum,
            restoreNotes: "Restore into a new local copy before replacing active records."
        )
    }
}

actor UsageLedger {
    func summarize(entries: [UsageLedgerEntry], providers: [AgentProviderProfile]) -> [UsageSnapshot] {
        UsageSnapshotBuilder.build(from: entries, providers: providers)
    }
}

actor ProviderSetupWizard {
    private let vault: KeychainVault

    init(vault: KeychainVault = KeychainVault()) {
        self.vault = vault
    }

    /// Build the install/verify summary that the wizard's first step renders.
    func setupPlan(for provider: AgentProviderSnapshot) -> ProviderSetupPlan {
        ProviderSetupPlan(
            providerID: provider.identifier,
            installCommand: provider.installCommand,
            verificationCommand: provider.verificationCommand,
            expectedBinary: provider.binaryName,
            requiresManualApproval: true,
            notes: "Install commands are displayed for user review only. Agenic Load-Balancer never runs installers silently."
        )
    }

    /// Persist an API key in the macOS Keychain. Returns the service/account
    /// pair that the caller should mirror into a `KeychainReferenceRecord`
    /// so SwiftData (and CloudKit metadata) can describe the credential
    /// without ever holding the secret itself.
    func saveAPIKey(
        for providerID: String,
        apiKey: String,
        purpose: String = "API key"
    ) async throws -> APIKeySaveResult {
        let service = Self.keychainService(for: providerID)
        let account = "api-key"
        try await vault.storeSecret(apiKey, service: service, account: account)
        return APIKeySaveResult(service: service, account: account, purpose: purpose)
    }

    /// Read a previously stored API key from the Keychain so the wizard can
    /// display a "credential saved" badge without leaking the value.
    func hasStoredAPIKey(for providerID: String) async -> Bool {
        let service = Self.keychainService(for: providerID)
        do {
            let value = try await vault.readSecret(service: service, account: "api-key")
            return value?.isEmpty == false
        } catch {
            return false
        }
    }

    /// Delete a stored API key. The caller still needs to remove the
    /// matching `KeychainReferenceRecord` from SwiftData.
    func clearAPIKey(for providerID: String) async {
        let service = Self.keychainService(for: providerID)
        try? await vault.removeSecret(service: service, account: "api-key")
    }

    /// Build a command profile draft seeded from the catalog default
    /// argument template. The template uses placeholder strings so the
    /// editor surfaces what gets substituted at run time.
    nonisolated func defaultCommandProfileDraft(
        for provider: AgentProviderSnapshot
    ) -> ProviderCommandProfileDraft {
        let lines = GenericCLIAdapter.defaultCommandArguments(
            for: provider.identifier,
            coordinationPrompt: "{{prompt}}",
            projectPath: "{{project}}",
            mode: .implementation
        )
        return ProviderCommandProfileDraft(
            providerID: provider.identifier,
            displayName: "\(provider.displayName) custom profile",
            executablePathOverride: nil,
            argumentTemplate: lines.joined(separator: "\n"),
            environmentJSON: "{}",
            isEnabled: false,
            notes: "Placeholders: {{prompt}} {{project}} {{mode}} {{provider_id}} are substituted at run time. Empty {{project}} substitutes an empty string — remove the line if your CLI requires the flag to be omitted entirely."
        )
    }

    private static func keychainService(for providerID: String) -> String {
        "com.zincoverde.Agenic-Load-Balancer.\(providerID)"
    }
}

struct ProviderSetupPlan: Sendable {
    let providerID: String
    let installCommand: String
    let verificationCommand: String
    let expectedBinary: String
    let requiresManualApproval: Bool
    let notes: String
}

struct APIKeySaveResult: Sendable {
    let service: String
    let account: String
    let purpose: String
}

struct ProviderCommandProfileDraft: Sendable {
    let providerID: String
    let displayName: String
    let executablePathOverride: String?
    let argumentTemplate: String
    let environmentJSON: String
    let isEnabled: Bool
    let notes: String
}

actor KeychainVault {
    func storeSecret(_ secret: String, service: String, account: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandledStatus(addStatus)
        }
    }

    func readSecret(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a stored secret. Silently no-ops on `errSecItemNotFound` so
    /// the caller can use this without first checking existence.
    func removeSecret(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainError.unhandledStatus(status)
    }
}

enum KeychainError: Error, Sendable, LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status): "Keychain operation failed with status \(status)."
        }
    }
}

@MainActor
final class OAuthSignInCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? OAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            if !session.start() {
                continuation.resume(throwing: OAuthError.failedToStart)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }
}

enum OAuthError: Error, Sendable, LocalizedError {
    case cancelled
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .cancelled: "OAuth flow was cancelled."
        case .failedToStart: "OAuth browser session could not be started."
        }
    }
}
