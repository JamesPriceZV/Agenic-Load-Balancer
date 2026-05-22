//
//  ReleaseReadinessTests.swift
//  Agenic Load-BalancerTests
//
//  Sprint H: release preflight and packaging guardrails.
//

import Foundation
import Testing
@testable import Agenic_Load_Balancer

@Suite("Release readiness")
struct ReleaseReadinessTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func entitlementsMatchCloudKitAndDeveloperToolPosture() throws {
        let entitlementsURL = Self.repositoryRoot
            .appendingPathComponent("Agenic Load-Balancer")
            .appendingPathComponent("Agenic_Load_Balancer.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let entitlements = try #require(plist as? [String: Any])

        let containers = try #require(entitlements["com.apple.developer.icloud-container-identifiers"] as? [String])
        let services = try #require(entitlements["com.apple.developer.icloud-services"] as? [String])
        let ubiquityContainers = try #require(entitlements["com.apple.developer.ubiquity-container-identifiers"] as? [String])

        #expect(containers == [AgenicDataModel.cloudKitContainerIdentifier])
        #expect(services.contains("CloudKit"))
        #expect(services.contains("CloudDocuments"))
        #expect(ubiquityContainers == [AgenicDataModel.cloudKitContainerIdentifier])
        #expect(entitlements["com.apple.developer.ubiquity-kvstore-identifier"] as? String == "$(TeamIdentifierPrefix)$(CFBundleIdentifier)")
        #expect(entitlements["com.apple.developer.aps-environment"] as? String == "development")

        // The current release lane is Developer ID / local developer tool.
        // App Sandbox would need a separate provider-execution design.
        #expect(entitlements["com.apple.security.app-sandbox"] == nil)
    }

    @Test func xcodeProjectDeclaresReleaseCriticalBuildSettings() throws {
        let pbxprojURL = Self.repositoryRoot
            .appendingPathComponent("Agenic Load-Balancer.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        let pbxproj = try String(contentsOf: pbxprojURL, encoding: .utf8)

        #expect(pbxproj.contains("PRODUCT_BUNDLE_IDENTIFIER = \"com.zincoverde.Agenic-Load-Balancer\";"))
        #expect(pbxproj.contains("CODE_SIGN_ENTITLEMENTS = \"Agenic Load-Balancer/Agenic_Load_Balancer.entitlements\";"))
        #expect(pbxproj.contains("ENABLE_HARDENED_RUNTIME = YES;"))
        #expect(pbxproj.contains("INFOPLIST_KEY_LSApplicationCategoryType = \"public.app-category.developer-tools\";"))
        #expect(pbxproj.contains("MACOSX_DEPLOYMENT_TARGET = 26.4;"))
        #expect(pbxproj.contains("MARKETING_VERSION = 1.0;"))
        #expect(pbxproj.contains("CURRENT_PROJECT_VERSION = 1;"))
    }

    @Test func releaseChecklistAndPreflightScriptStayWired() throws {
        let root = Self.repositoryRoot
        let releaseDoc = try String(
            contentsOf: root.appendingPathComponent("ReleaseReadiness.md"),
            encoding: .utf8
        )
        let script = try String(
            contentsOf: root.appendingPathComponent("script/release_preflight.sh"),
            encoding: .utf8
        )
        let releaseCandidateScript = try String(
            contentsOf: root.appendingPathComponent("script/release_candidate.sh"),
            encoding: .utf8
        )

        #expect(releaseDoc.contains("Developer ID"))
        #expect(releaseDoc.contains("notarytool"))
        #expect(releaseDoc.contains("stapler"))
        #expect(releaseDoc.contains("Keychain"))
        #expect(releaseDoc.contains("Rollback Plan"))
        #expect(releaseDoc.contains("script/release_candidate.sh --all"))

        #expect(script.contains("ENABLE_HARDENED_RUNTIME = YES"))
        #expect(script.contains("com.apple.developer.icloud-services"))
        #expect(script.contains("--signed-build"))
        #expect(script.contains("xcodebuild"))

        #expect(releaseCandidateScript.contains("Developer ID Application"))
        #expect(releaseCandidateScript.contains("security find-identity"))
        #expect(releaseCandidateScript.contains("xcodebuild archive"))
        #expect(releaseCandidateScript.contains("xcrun notarytool submit"))
        #expect(releaseCandidateScript.contains("xcrun stapler staple"))
        #expect(releaseCandidateScript.contains("spctl -a -vv --type execute"))
        #expect(releaseCandidateScript.contains("NOTARY_PROFILE"))
    }
}
