//
//  Agenic_Load_BalancerApp.swift
//  Agenic Load-Balancer
//
//  Created by Zinco Verde on 5/5/26.
//

import SwiftData
import SwiftUI

enum AgenicLaunchEnvironment {
    static func usesVolatileStore(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if arguments.contains("--uitesting") { return true }

        let xctestKeys = [
            "XCTestConfigurationFilePath",
            "XCTestSessionIdentifier",
            "XCInjectBundleInto",
        ]
        return xctestKeys.contains { environment[$0]?.isEmpty == false }
    }
}

@main
struct Agenic_Load_BalancerApp: App {
    var sharedModelContainer: ModelContainer = {
        Agenic_Load_BalancerApp.makeSharedModelContainer()
    }()

    /// Build the app's master SwiftData container with a layered recovery
    /// strategy:
    ///
    /// 1. CloudKit-backed private store (`AgenicCloudRepository`) — preferred
    ///    so the dashboard, restore center, and AgentNotes ledger sync across
    ///    the user's iCloud devices.
    /// 2. Local SQLite fallback (`AgenicLocalFallbackRepository`) — used when
    ///    CloudKit isn't reachable (no signed-in iCloud account, missing
    ///    entitlements during local dev, or schema validation that's
    ///    CloudKit-only).
    /// 3. Local SQLite fallback after wiping a stale on-disk store — handles
    ///    the case where a previous build wrote a SQLite file whose schema
    ///    can't be auto-migrated to the current model graph.
    /// 4. In-memory store of last resort so the app still launches and the
    ///    user can read the diagnostic banner instead of getting a fatal
    ///    crash on the splash screen.
    ///
    /// Each step logs the underlying SwiftData error so the actual failure
    /// is visible in Console.app even when the user only sees the recovered
    /// state in the UI.
    private static func makeSharedModelContainer() -> ModelContainer {
        let schema = AgenicDataModel.schema

        if AgenicLaunchEnvironment.usesVolatileStore() {
            let configuration = ModelConfiguration(
                "AgenicVolatileTestingRepository",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create in-memory testing container: \(error)")
            }
        }

        // Step 1: CloudKit-backed private store.
        let cloudConfiguration = ModelConfiguration(
            "AgenicCloudRepository",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(AgenicDataModel.cloudKitContainerIdentifier)
        )
        do {
            return try ModelContainer(for: schema, configurations: [cloudConfiguration])
        } catch {
            log("CloudKit-backed SwiftData container unavailable; falling back to local store. error=\(error)")
        }

        // Step 2: plain on-disk fallback.
        let fallbackConfiguration = ModelConfiguration(
            "AgenicLocalFallbackRepository",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
        } catch {
            log("Local fallback SwiftData container failed; attempting stale-store wipe. error=\(error)")
        }

        // Step 3: wipe any stale on-disk SwiftData stores left over from a
        // prior schema and try again.
        wipeStaleStores(named: ["AgenicCloudRepository", "AgenicLocalFallbackRepository"])
        do {
            return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
        } catch {
            log("Local fallback still failing after wipe; using in-memory store. error=\(error)")
        }

        // Step 4: in-memory store of last resort. The app launches, surfaces
        // the failure to the user, and avoids a launch-time crash.
        let memoryConfiguration = ModelConfiguration(
            "AgenicMemoryRecoveryRepository",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [memoryConfiguration])
        } catch {
            fatalError("Could not create Agenic SwiftData container (even in-memory): \(error)")
        }
    }

    /// Best-effort delete of any `<name>.store`, `<name>.store-shm`,
    /// `<name>.store-wal`, and CloudKit-companion files in the app's
    /// Application Support directory. Errors are intentionally swallowed —
    /// this is a recovery path; we'd rather try the next step than crash.
    private static func wipeStaleStores(named names: [String]) {
        let fileManager = FileManager.default
        guard let supportDirectory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.zincoverde.Agenic-Load-Balancer"
        // SwiftData on macOS resolves named configurations under the bundle's
        // own subdirectory; the iOS path is identical for unsigned macs.
        let storeRoots: [URL] = [
            supportDirectory.appendingPathComponent(bundleID, isDirectory: true),
            supportDirectory,
        ]

        let suffixes = [".store", ".store-shm", ".store-wal", ".store.ckAssetFiles"]
        for root in storeRoots {
            for name in names {
                for suffix in suffixes {
                    let candidate = root.appendingPathComponent("\(name)\(suffix)")
                    if fileManager.fileExists(atPath: candidate.path) {
                        do {
                            try fileManager.removeItem(at: candidate)
                            log("Removed stale SwiftData artifact at \(candidate.path)")
                        } catch {
                            log("Failed to remove stale SwiftData artifact at \(candidate.path): \(error)")
                        }
                    }
                }
            }
        }
    }

    private static func log(_ message: String) {
        // Plain print so the message lands in Xcode's console without
        // requiring an os.Logger import in this bootstrap path.
        print("[Agenic][SwiftData] \(message)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView()
                .modelContainer(sharedModelContainer)
        }
    }
}

enum AgenicSettingsTab: String, CaseIterable, Identifiable {
    case generation
    case context
    case tools
    case agents
    case server
    case memory
    case storage
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generation: "Generation"
        case .context: "Context"
        case .tools: "Tools"
        case .agents: "Agents"
        case .server: "Server"
        case .memory: "Memory"
        case .storage: "Storage"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .generation: "wand.and.stars"
        case .context: "globe.americas"
        case .tools: "hammer"
        case .agents: "person.3"
        case .server: "network"
        case .memory: "memorychip"
        case .storage: "externaldrive"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Query private var providers: [AgentProviderProfile]
    @Query private var projects: [AgentProject]
    @Query private var keychainReferences: [KeychainReferenceRecord]
    @Query private var snapshots: [CloudSnapshotRecord]

    @AppStorage("Agenic.defaultMaxTokens") private var defaultMaxTokens = 1024
    @AppStorage("Agenic.temperature") private var temperature = 0.6
    @AppStorage("Agenic.requireMutatingActionApproval") private var requireMutatingActionApproval = true
    @AppStorage("Agenic.allowToolCalling") private var allowToolCalling = true
    @AppStorage("Agenic.allowShellTools") private var allowShellTools = true
    @AppStorage("Agenic.allowNetworkSearch") private var allowNetworkSearch = false
    @AppStorage("Agenic.allowFilesystemWrites") private var allowFilesystemWrites = true
    @AppStorage("Agenic.defaultWorkingPath") private var defaultWorkingPath = ""
    @AppStorage("Agenic.defaultTemporaryPath") private var defaultTemporaryPath = ""
    @AppStorage("Agenic.contextCompactionEnabled") private var contextCompactionEnabled = true
    @AppStorage("Agenic.contextCompactionThresholdTokens") private var contextCompactionThresholdTokens = 120_000
    @AppStorage("Agenic.summaryBufferCharacterLimit") private var summaryBufferCharacterLimit = RunSummaryInput.maxBufferBytes

    @State private var selectedTab: AgenicSettingsTab
    @State private var cloudStatus = CloudSyncStatusSnapshot(
        containerIdentifier: AgenicDataModel.cloudKitContainerIdentifier,
        lastLocalSave: nil,
        lastCloudEvent: nil,
        status: "loading",
        detail: "Checking CloudKit-backed SwiftData status."
    )
    @State private var foundationModelsAvailability = SystemLanguageModelAvailabilityChecker().currentAvailability()
    @State private var foundationModelsReport: FoundationModelsDiagnosticReport?
    @State private var foundationModelsDiagnosticsRunning = false

    init(initialTab: AgenicSettingsTab = .generation) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider().opacity(0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(selectedTab.title)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    selectedPane
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(28)
            }
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 600, idealHeight: 720)
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                AgenicTheme.detailBackground.opacity(0.48)
            }
        }
        .task {
            await refreshCloudStatus()
            refreshFoundationModelsAvailability()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                dismiss()
            } label: {
                Label("Back to app", systemImage: "chevron.left")
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(AgenicSettingsTab.allCases) { tab in
                    settingsTabButton(tab)
                }
            }

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 4) {
                Label(cloudStatus.status.capitalized, systemImage: "icloud")
                    .font(.caption.weight(.semibold))
                Text(cloudStatus.containerIdentifier)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(20)
        .frame(width: 240)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(AgenicTheme.settingsSidebarTint)
        }
    }

    private func settingsTabButton(_ tab: AgenicSettingsTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20)
                Text(tab.title)
                    .font(.callout.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
        .background {
            if selectedTab == tab {
                RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        Color.accentColor.opacity(0.12),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                .stroke(selectedTab == tab ? Color.white.opacity(0.10) : Color.clear, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch selectedTab {
        case .generation:
            settingsSection("Sampling") {
                HStack {
                    Text("Temperature")
                    Slider(value: $temperature, in: 0...1)
                    Text(temperature, format: .number.precision(.fractionLength(2)))
                        .font(.body.monospacedDigit())
                        .frame(width: 54, alignment: .trailing)
                }
                Stepper(value: $defaultMaxTokens, in: 256...32_768, step: 256) {
                    LabeledContent("Max tokens", value: "\(defaultMaxTokens.formatted())")
                }
            }
        case .context:
            settingsSection("Projects") {
                settingsRow("Workspaces", "\(projects.count)")
                settingsRow("Prompt excerpt sync", "\(projects.filter(\.promptExcerptSyncEnabled).count) enabled")
                settingsRow("Heatmap providers", "Configured only")
            }
            settingsSection("Compaction") {
                settingsToggleRow("Compact long provider output before AI summaries", isOn: $contextCompactionEnabled)
                Stepper(value: $contextCompactionThresholdTokens, in: 8_000...1_000_000, step: 8_000) {
                    LabeledContent("Context threshold", value: "\(contextCompactionThresholdTokens.formatted()) tokens")
                }
                Stepper(value: $summaryBufferCharacterLimit, in: 512...24_000, step: 512) {
                    LabeledContent("Summary transcript cap", value: "\(summaryBufferCharacterLimit.formatted()) chars per stream")
                }
            }
        case .tools:
            settingsSection("Command Bar") {
                settingsToggleRow("Require approval for mutating actions", isOn: $requireMutatingActionApproval)
                settingsRow("Tool actions", "Rank, Dispatch, Probe, Snapshot, Reconcile, Metrics")
                settingsRow("Dispatch behavior", "Approval-gated run drafts")
            }
            settingsSection("Default Tool Permissions") {
                settingsToggleRow("Allow tool calling", isOn: $allowToolCalling)
                settingsToggleRow("Allow shell tools", isOn: $allowShellTools)
                settingsToggleRow("Allow network search", isOn: $allowNetworkSearch)
                settingsToggleRow("Allow filesystem writes", isOn: $allowFilesystemWrites)
            }
        case .agents:
            settingsSection("Providers") {
                settingsRow("Catalog entries", "\(providers.count)")
                settingsRow("Configured", "\(providers.filter(\.isConfiguredForDashboard).count)")
                settingsRow("Available", "\(providers.filter { $0.installedState == ProviderAvailabilityState.available.rawValue }.count)")
                settingsRow("Credential references", "\(keychainReferences.count)")
            }
            foundationModelsDiagnosticsSection
        case .server:
            settingsSection("Execution") {
                settingsRow("Runner", "Local process + Foundation Models composite")
                settingsRow("Approval model", "Approve then run")
                settingsRow("Secrets", "Keychain references only")
            }
            settingsSection("Default Paths") {
                TextField("Default working path", text: $defaultWorkingPath)
                    .textFieldStyle(.roundedBorder)
                TextField("Default temporary path", text: $defaultTemporaryPath)
                    .textFieldStyle(.roundedBorder)
                Text("Project settings override these defaults for runs launched from a configured workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .memory:
            settingsSection("AgentNotes") {
                settingsRow("Default file", "AgentNotes.md")
                settingsRow("Coordination source", "SwiftData ledger projection")
                settingsRow("Projects with folders", "\(projects.filter { ($0.rootPath?.isEmpty == false) }.count)")
            }
        case .storage:
            settingsSection("Repository") {
                settingsRow("SwiftData", "Master local repository")
                settingsRow("CloudKit", cloudStatus.containerIdentifier)
                settingsRow("Status", cloudStatus.status.capitalized)
                settingsRow("Detail", cloudStatus.detail)
                settingsRow("Snapshots", "\(snapshots.count)")
                settingsRow("Last local save", cloudStatus.lastLocalSave?.formatted(date: .abbreviated, time: .standard) ?? "Not recorded")
                settingsRow("Last cloud event", cloudStatus.lastCloudEvent?.formatted(date: .abbreviated, time: .standard) ?? "Not recorded")
                Button {
                    Task { await refreshCloudStatus() }
                } label: {
                    Label("Refresh iCloud Status", systemImage: "arrow.triangle.2.circlepath.icloud")
                }
            }
        case .about:
            settingsSection("Agenic Load-Balancer") {
                settingsRow("Version", appVersion)
                settingsRow("CloudKit container", AgenicDataModel.cloudKitContainerIdentifier)
                settingsRow("Data policy", "Workspace secrets stay out of SwiftData and CloudKit")
            }
        }
    }

    @ViewBuilder
    private var foundationModelsDiagnosticsSection: some View {
        settingsSection("Foundation Models Diagnostics") {
            settingsRow("Availability", foundationModelsAvailability.message)
            if let foundationModelsReport {
                settingsRow("Last run", foundationModelsReport.finishedAt.formatted(date: .abbreviated, time: .standard))
                settingsRow("Status", foundationModelsReport.statusSummary)
                ForEach(foundationModelsReport.probes) { probe in
                    foundationModelsProbeRow(probe)
                }
            }
            Button {
                Task { await runFoundationModelsDiagnostics() }
            } label: {
                HStack(spacing: 8) {
                    if foundationModelsDiagnosticsRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.seal")
                    }
                    Text(foundationModelsDiagnosticsRunning ? "Running diagnostics" : "Run diagnostics")
                }
            }
            .disabled(foundationModelsDiagnosticsRunning)
            .padding(.top, 8)
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                            .fill(AgenicTheme.glassTint)
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AgenicTheme.cornerRadius)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, y: 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 18)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }

    private func settingsToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 18)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }

    private func foundationModelsProbeRow(_ probe: FoundationModelsDiagnosticProbeResult) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(probe.kind.title)
            Spacer(minLength: 18)
            VStack(alignment: .trailing, spacing: 3) {
                Text(probe.status.label)
                    .foregroundStyle(foundationModelsStatusColor(probe.status))
                    .font(.body.weight(.semibold))
                Text(probe.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if probe.durationSeconds > 0 {
                    Text(probe.durationSeconds, format: .number.precision(.fractionLength(2)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    private func refreshCloudStatus() async {
        let status = await AppServices.cloudSync.currentStatus()
        await MainActor.run {
            cloudStatus = status
        }
    }

    private func refreshFoundationModelsAvailability() {
        foundationModelsAvailability = SystemLanguageModelAvailabilityChecker().currentAvailability()
    }

    private func runFoundationModelsDiagnostics() async {
        await MainActor.run {
            foundationModelsDiagnosticsRunning = true
        }
        let report = await FoundationModelsDiagnosticsRunner().run()
        await MainActor.run {
            foundationModelsReport = report
            foundationModelsAvailability = report.availability
            foundationModelsDiagnosticsRunning = false
        }
    }

    private func foundationModelsStatusColor(_ status: FoundationModelsDiagnosticProbeStatus) -> Color {
        switch status {
        case .succeeded: .green
        case .skipped: .orange
        case .failed: .red
        }
    }
}
