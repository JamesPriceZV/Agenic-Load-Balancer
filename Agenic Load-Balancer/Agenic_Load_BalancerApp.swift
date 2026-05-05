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
                .frame(minWidth: 1100, minHeight: 720)
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

private struct SettingsView: View {
    @Query private var providers: [AgentProviderProfile]
    @Query private var keychainReferences: [KeychainReferenceRecord]

    var body: some View {
        Form {
            Section("Repository") {
                LabeledContent("SwiftData", value: "Master local repository")
                LabeledContent("CloudKit", value: AgenicDataModel.cloudKitContainerIdentifier)
                LabeledContent("Secrets", value: "Keychain references only")
            }

            Section("Providers") {
                LabeledContent("Configured", value: "\(providers.count)")
                LabeledContent("Credential References", value: "\(keychainReferences.count)")
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(width: 520)
    }
}
