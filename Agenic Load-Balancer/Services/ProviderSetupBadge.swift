//
//  ProviderSetupBadge.swift
//  Agenic Load-Balancer
//
//  Sprint P.2: derive deterministic provider-setup status badges from
//  `AgentProviderProfile`, `ProviderSetupRecord`, `KeychainReferenceRecord`,
//  and `ProviderAuthRecipe`. Surfaces account-login freshness, API-key
//  reference health, missing-binary remediation hints, and a single
//  rolled-up `ProviderSetupBadgeSummary.overallTone` the catalog UI uses
//  to render the row chip color without re-implementing the rules.
//
//  This is intentionally a value-type module with no SwiftData reads of
//  its own; the caller fetches the records once and hands them in. Keeps
//  it Sendable, easy to test, and safe to call from the main actor with
//  fixture data in UI tests.
//

import Foundation

/// Visual + behavioural tone shared across all badges so callers can paint
/// them consistently. Ordered worst → best so callers can compute the
/// roll-up by taking `max(byTone:)` over the set.
enum ProviderSetupBadgeTone: String, Sendable, Hashable, CaseIterable, Comparable {
    case attention
    case warning
    case neutral
    case healthy

    static func < (lhs: ProviderSetupBadgeTone, rhs: ProviderSetupBadgeTone) -> Bool {
        lhs.severity < rhs.severity
    }

    /// Numeric severity used for ordering. Smaller = needs the user's
    /// attention more urgently.
    var severity: Int {
        switch self {
        case .attention: 0
        case .warning: 1
        case .neutral: 2
        case .healthy: 3
        }
    }

    /// Optional system-image suggestion the catalog row can render. The
    /// view layer can ignore this and pick its own icons.
    var systemImage: String {
        switch self {
        case .attention: "exclamationmark.octagon"
        case .warning: "exclamationmark.triangle"
        case .neutral: "info.circle"
        case .healthy: "checkmark.seal"
        }
    }
}

/// Kind of state a badge describes so the UI can group/sort them and
/// tests can pick a specific badge without depending on label text.
enum ProviderSetupBadgeKind: String, Sendable, Hashable, CaseIterable {
    case binary
    case auth
    case credentials
    case freshness
}

/// One badge slot for a single provider.
struct ProviderSetupBadge: Sendable, Hashable, Identifiable {
    let providerID: String
    let kind: ProviderSetupBadgeKind
    let tone: ProviderSetupBadgeTone
    /// Short label shown inside the badge chip (e.g. "Missing", "Authenticated").
    let label: String
    /// One-line user-readable explanation rendered under the chip.
    let detail: String
    /// Optional remediation hint — actionable copy or a CLI command the
    /// user can run. The UI may render it as a code chip.
    let remediation: String?

    var id: String { "\(providerID).\(kind.rawValue)" }
}

/// Aggregate over the four badge slots for one provider. `overallTone`
/// is the minimum (worst) tone across the badges so the catalog row can
/// pick a single chip color.
struct ProviderSetupBadgeSummary: Sendable, Hashable, Identifiable {
    let providerID: String
    let providerName: String
    let badges: [ProviderSetupBadge]
    let overallTone: ProviderSetupBadgeTone
    let summary: String

    var id: String { providerID }

    func badge(of kind: ProviderSetupBadgeKind) -> ProviderSetupBadge? {
        badges.first(where: { $0.kind == kind })
    }
}

enum ProviderSetupBadgeBuilder {
    /// Hard-cutoff windows used to decide health-check freshness. The UI
    /// can adjust these by passing `freshWindow` / `staleWindow` but the
    /// defaults are deliberately conservative because account login can
    /// silently expire on the provider side.
    struct FreshnessWindows: Sendable, Hashable {
        let fresh: TimeInterval
        let stale: TimeInterval

        static let defaultWindows = FreshnessWindows(
            fresh: 60 * 60 * 24 * 7,        // 7 days
            stale: 60 * 60 * 24 * 30        // 30 days
        )
    }

    static func summaries(
        providers: [AgentProviderProfile],
        setups: [ProviderSetupRecord],
        keychainReferences: [KeychainReferenceRecord],
        recipes: (String) -> ProviderAuthRecipe = ProviderAuthRecipe.recipe(for:),
        freshnessWindows: FreshnessWindows = .defaultWindows,
        now: () -> Date = Date.init
    ) -> [ProviderSetupBadgeSummary] {
        let setupByProvider = Dictionary(grouping: setups, by: \.providerID)
            .mapValues { $0.sorted(by: { $0.updatedAt > $1.updatedAt }).first }
        let keychainByProvider = Dictionary(grouping: keychainReferences, by: \.providerID)

        let evaluation = now()

        return providers.map { provider in
            let setup = setupByProvider[provider.identifier] ?? nil
            let refs = keychainByProvider[provider.identifier] ?? []
            let recipe = recipes(provider.identifier)

            let binary = binaryBadge(provider: provider)
            let auth = authBadge(provider: provider, recipe: recipe, setup: setup)
            let credentials = credentialBadge(
                provider: provider,
                recipe: recipe,
                references: refs
            )
            let freshness = freshnessBadge(
                provider: provider,
                evaluation: evaluation,
                windows: freshnessWindows
            )

            let badges = [binary, auth, credentials, freshness]
            let overall = badges.map(\.tone).min() ?? .neutral
            let summary = badges
                .filter { $0.tone != .healthy }
                .map { "\($0.kind.rawValue.capitalized): \($0.label)" }
                .joined(separator: " · ")
            return ProviderSetupBadgeSummary(
                providerID: provider.identifier,
                providerName: provider.displayName,
                badges: badges,
                overallTone: overall,
                summary: summary.isEmpty ? "All setup checks healthy." : summary
            )
        }
    }

    // MARK: - Individual badge rules

    private static func binaryBadge(provider: AgentProviderProfile) -> ProviderSetupBadge {
        let state = ProviderAvailabilityState(rawValue: provider.installedState) ?? .unknown
        switch state {
        case .available:
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .binary,
                tone: .healthy,
                label: "Installed",
                detail: provider.lastDetectedVersion.map { "Detected version: \($0)." } ?? "Provider binary is on PATH.",
                remediation: nil
            )
        case .missing:
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .binary,
                tone: .attention,
                label: "Missing",
                detail: "`\(provider.binaryName)` is not on PATH.",
                remediation: provider.installCommand.isEmpty ? nil : provider.installCommand
            )
        case .disabled:
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .binary,
                tone: .warning,
                label: "Disabled",
                detail: "Provider is disabled in this workspace.",
                remediation: nil
            )
        case .error:
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .binary,
                tone: .attention,
                label: "Errored",
                detail: "Last probe reported an unrecoverable error.",
                remediation: provider.verificationCommand.isEmpty ? nil : provider.verificationCommand
            )
        case .unknown:
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .binary,
                tone: .neutral,
                label: "Unknown",
                detail: "No availability probe has run yet.",
                remediation: provider.verificationCommand.isEmpty ? nil : provider.verificationCommand
            )
        }
    }

    private static func authBadge(
        provider: AgentProviderProfile,
        recipe: ProviderAuthRecipe,
        setup: ProviderSetupRecord?
    ) -> ProviderSetupBadge {
        let state = ProviderAuthState(rawValue: provider.authState) ?? .unknown
        switch state {
        case .authenticated:
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .auth,
                tone: .healthy,
                label: "Authenticated",
                detail: "Last probe reported a working session.",
                remediation: nil
            )
        case .needsToken:
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .auth,
                tone: .attention,
                label: "Needs token",
                detail: recipe.apiKeyEnvironmentVariables.isEmpty
                    ? "Provider needs an API key or token."
                    : "Set one of: \(recipe.apiKeyEnvironmentVariables.joined(separator: ", "))",
                remediation: recipe.apiKeyEnvironmentVariables.first.map { "export \($0)=<value>" }
            )
        case .browserLoginRequired:
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .auth,
                tone: .warning,
                label: "Browser login",
                detail: "Account login must be completed in a browser.",
                remediation: recipe.authProbeCommands.first?.command
            )
        case .custom:
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .auth,
                tone: .neutral,
                label: "Custom",
                detail: "Custom credentials are configured.",
                remediation: nil
            )
        case .unauthenticated:
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .auth,
                tone: .attention,
                label: "Unauthenticated",
                detail: setup?.lastError ?? "Last auth probe could not verify credentials.",
                remediation: recipe.authProbeCommands.first?.command
            )
        case .unknown:
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .auth,
                tone: .neutral,
                label: "Unknown",
                detail: "No auth probe has run yet.",
                remediation: recipe.authProbeCommands.first?.command
            )
        }
    }

    private static func credentialBadge(
        provider: AgentProviderProfile,
        recipe: ProviderAuthRecipe,
        references: [KeychainReferenceRecord]
    ) -> ProviderSetupBadge {
        // No API-key lane at all → credential badge is not applicable.
        if recipe.apiKeyEnvironmentVariables.isEmpty && references.isEmpty {
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .credentials,
                tone: .healthy,
                label: "No secret",
                detail: "Provider does not require an API key reference.",
                remediation: nil
            )
        }
        if references.isEmpty {
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .credentials,
                tone: .warning,
                label: "Not linked",
                detail: "No Keychain reference is linked yet.",
                remediation: recipe.apiKeyEnvironmentVariables.first.map { "Store secret in Keychain and link it to \(provider.displayName); env var \($0)" }
            )
        }
        let oldest = references.map(\.updatedAt).min() ?? Date.distantPast
        let ageDays = Calendar.current.dateComponents([.day], from: oldest, to: Date()).day ?? 0
        return ProviderSetupBadge(
            providerID: provider.identifier,
            kind: .credentials,
            tone: .healthy,
            label: "Linked",
            detail: "\(references.count) Keychain reference(s); oldest updated \(ageDays) day(s) ago.",
            remediation: nil
        )
    }

    private static func freshnessBadge(
        provider: AgentProviderProfile,
        evaluation: Date,
        windows: FreshnessWindows
    ) -> ProviderSetupBadge {
        guard let lastCheck = provider.lastHealthCheckAt else {
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .freshness,
                tone: .warning,
                label: "Never checked",
                detail: "Run the provider probe to record an availability check.",
                remediation: provider.verificationCommand.isEmpty ? nil : provider.verificationCommand
            )
        }
        let age = evaluation.timeIntervalSince(lastCheck)
        if age <= windows.fresh {
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .freshness,
                tone: .healthy,
                label: "Fresh",
                detail: "Last probe \(Int(age / 3600)) hour(s) ago.",
                remediation: nil
            )
        }
        if age <= windows.stale {
            return ProviderSetupBadge(
                providerID: provider.identifier,
                kind: .freshness,
                tone: .neutral,
                label: "Aging",
                detail: "Last probe \(Int(age / 86_400)) day(s) ago; consider re-probing.",
                remediation: nil
            )
        }
        return ProviderSetupBadge(
            providerID: provider.identifier,
            kind: .freshness,
            tone: .warning,
            label: "Stale",
            detail: "Last probe \(Int(age / 86_400)) day(s) ago; account state may have drifted.",
            remediation: provider.verificationCommand.isEmpty ? nil : provider.verificationCommand
        )
    }
}
