//
//  ProviderSetupBadgeTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint P.2: deterministic provider-setup status badge derivation.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Provider setup badges")
struct ProviderSetupBadgeTests {
    private func provider(
        identifier: String = "openai.codex",
        installed: ProviderAvailabilityState = .available,
        auth: ProviderAuthState = .authenticated,
        lastHealthCheckAt: Date? = Date()
    ) -> AgentProviderProfile {
        let draft = ProviderCatalog.defaultProfiles[0]
        let profile = AgentProviderProfile(draft: draft)
        profile.identifier = identifier
        profile.installedState = installed.rawValue
        profile.authState = auth.rawValue
        profile.lastDetectedVersion = installed == .available ? "1.0" : nil
        profile.lastHealthCheckAt = lastHealthCheckAt
        return profile
    }

    @Test func healthyProviderRollsUpAllGreenBadges() {
        let profile = provider()
        let setups: [ProviderSetupRecord] = []
        let refs = [
            KeychainReferenceRecord(
                providerID: profile.identifier,
                serviceName: "Agenic.openai.codex",
                accountName: "default",
                purpose: "API key"
            ),
        ]

        let summary = ProviderSetupBadgeBuilder.summaries(
            providers: [profile],
            setups: setups,
            keychainReferences: refs
        ).first!

        #expect(summary.badges.count == 4)
        #expect(summary.overallTone == .healthy)
        #expect(summary.summary == "All setup checks healthy.")
        #expect(summary.badge(of: .binary)?.tone == .healthy)
        #expect(summary.badge(of: .auth)?.tone == .healthy)
        #expect(summary.badge(of: .credentials)?.tone == .healthy)
        #expect(summary.badge(of: .freshness)?.tone == .healthy)
    }

    @Test func missingBinaryProducesAttentionBadgeAndRemediation() {
        let profile = provider(installed: .missing, auth: .unknown, lastHealthCheckAt: nil)

        let summary = ProviderSetupBadgeBuilder.summaries(
            providers: [profile],
            setups: [],
            keychainReferences: []
        ).first!

        let binary = try! #require(summary.badge(of: .binary))
        #expect(binary.tone == .attention)
        #expect(binary.label == "Missing")
        #expect(binary.remediation != nil)
        #expect(summary.overallTone == .attention)
    }

    @Test func needsTokenAuthSurfacesEnvironmentVariableRemediation() {
        let profile = provider(auth: .needsToken)

        let summary = ProviderSetupBadgeBuilder.summaries(
            providers: [profile],
            setups: [],
            keychainReferences: []
        ).first!

        let auth = try! #require(summary.badge(of: .auth))
        #expect(auth.tone == .attention)
        #expect(auth.label == "Needs token")
        #expect(auth.detail.contains("OPENAI_API_KEY"))
        #expect(auth.remediation?.contains("OPENAI_API_KEY") == true)
    }

    @Test func freshnessBadgeAgesThroughThresholds() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let freshProvider = provider(lastHealthCheckAt: now.addingTimeInterval(-3_600 * 12))
        let agingProvider = provider(
            identifier: "anthropic.claude-code",
            lastHealthCheckAt: now.addingTimeInterval(-60 * 60 * 24 * 14)
        )
        let staleProvider = provider(
            identifier: "google.gemini-cli",
            lastHealthCheckAt: now.addingTimeInterval(-60 * 60 * 24 * 90)
        )

        let summaries = ProviderSetupBadgeBuilder.summaries(
            providers: [freshProvider, agingProvider, staleProvider],
            setups: [],
            keychainReferences: [],
            now: { now }
        )

        #expect(summaries[0].badge(of: .freshness)?.tone == .healthy)
        #expect(summaries[1].badge(of: .freshness)?.tone == .neutral)
        #expect(summaries[2].badge(of: .freshness)?.tone == .warning)
    }

    @Test func credentialsBadgeWarnsWhenAPIRecipeButNoKeychainReference() {
        let profile = provider(auth: .needsToken)

        let summary = ProviderSetupBadgeBuilder.summaries(
            providers: [profile],
            setups: [],
            keychainReferences: []
        ).first!

        let credentials = try! #require(summary.badge(of: .credentials))
        #expect(credentials.tone == .warning)
        #expect(credentials.label == "Not linked")
        #expect(credentials.remediation?.contains("OPENAI_API_KEY") == true)
    }

    @Test func overallToneIsTheWorstBadge() {
        let profile = provider(installed: .available, auth: .unauthenticated, lastHealthCheckAt: Date())
        let setup = ProviderSetupRecord(
            providerID: profile.identifier,
            setupStage: "auth",
            lastAction: "probe",
            lastError: "401 from /v1/models",
            installConfirmed: true,
            authConfirmed: false
        )

        let summary = ProviderSetupBadgeBuilder.summaries(
            providers: [profile],
            setups: [setup],
            keychainReferences: []
        ).first!

        let auth = try! #require(summary.badge(of: .auth))
        #expect(auth.tone == .attention)
        #expect(auth.detail == "401 from /v1/models")
        #expect(summary.overallTone == .attention)
        #expect(summary.summary.contains("Auth: Unauthenticated"))
    }

    @Test func toneOrderingPicksWorstBadgeForRollup() {
        let tones: [ProviderSetupBadgeTone] = [.healthy, .warning, .neutral, .attention]
        #expect(tones.min() == .attention)
        #expect(tones.max() == .healthy)
    }
}
