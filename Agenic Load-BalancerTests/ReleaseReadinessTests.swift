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
        #expect(releaseCandidateScript.contains("archive_app()"))
        #expect(releaseCandidateScript.contains("xcodebuild"))
        #expect(releaseCandidateScript.contains("xcrun notarytool submit"))
        #expect(releaseCandidateScript.contains("xcrun stapler staple"))
        #expect(releaseCandidateScript.contains("spctl -a -vv --type execute"))
        #expect(releaseCandidateScript.contains("NOTARY_PROFILE"))
    }

    @Test func liveMaturityDoctorScriptsStayWired() throws {
        let root = Self.repositoryRoot
        let scriptRoot = root.appendingPathComponent("script")
        let liveMaturity = try String(
            contentsOf: scriptRoot.appendingPathComponent("live_maturity_check.sh"),
            encoding: .utf8
        )
        let providerMaintenance = try String(
            contentsOf: scriptRoot.appendingPathComponent("provider_probe_maintenance.sh"),
            encoding: .utf8
        )
        let foundationModels = try String(
            contentsOf: scriptRoot.appendingPathComponent("foundation_models_check.sh"),
            encoding: .utf8
        )
        let cloudKitDrill = try String(
            contentsOf: scriptRoot.appendingPathComponent("cloudkit_conflict_drill.sh"),
            encoding: .utf8
        )
        let twoMacCloudKitDrill = try String(
            contentsOf: scriptRoot.appendingPathComponent("two_mac_cloudkit_drill.sh"),
            encoding: .utf8
        )
        let autonomyDrill = try String(
            contentsOf: scriptRoot.appendingPathComponent("autonomy_continuation_drill.sh"),
            encoding: .utf8
        )
        let releaseCandidate = try String(
            contentsOf: scriptRoot.appendingPathComponent("release_candidate.sh"),
            encoding: .utf8
        )
        let visualRegression = try String(
            contentsOf: scriptRoot.appendingPathComponent("visual_regression.sh"),
            encoding: .utf8
        )

        #expect(liveMaturity.contains("--foundation-models"))
        #expect(liveMaturity.contains("--cloudkit-conflict"))
        #expect(liveMaturity.contains("--two-mac-cloudkit"))
        #expect(liveMaturity.contains("--visual"))
        #expect(liveMaturity.contains("release_candidate.sh"))
        #expect(liveMaturity.contains("provider_probe_maintenance.sh"))

        #expect(providerMaintenance.contains("BASELINE_REPORT"))
        #expect(providerMaintenance.contains("provider_probe_report.sh"))
        #expect(providerMaintenance.contains("diff -u"))

        #expect(foundationModels.contains("SystemLanguageModel.default.availability"))
        #expect(foundationModels.contains("LanguageModelSession"))
        #expect(foundationModels.contains("response=skipped"))

        #expect(cloudKitDrill.contains("--role local|primary|secondary"))
        #expect(cloudKitDrill.contains("PlistBuddy"))
        #expect(cloudKitDrill.contains("CloudKit container"))
        #expect(cloudKitDrill.contains("Passing that rehearsal is necessary but not sufficient"))
        #expect(twoMacCloudKitDrill.contains("Solaris971.local"))
        #expect(twoMacCloudKitDrill.contains("--require-ssh"))
        #expect(twoMacCloudKitDrill.contains("Remote Login/SSH did not capture peer evidence"))
        // Sprint O.4: peer bundle, sha256 verification, resume, and the
        // Remote Login runbook printer must stay wired.
        #expect(twoMacCloudKitDrill.contains("--peer-bundle"))
        #expect(twoMacCloudKitDrill.contains("--verify-peer-evidence"))
        #expect(twoMacCloudKitDrill.contains("--resume"))
        #expect(twoMacCloudKitDrill.contains("--remote-login-runbook"))
        #expect(twoMacCloudKitDrill.contains("Sprint O.4 — Solaris971 Remote Login / SSH enablement runbook"))
        #expect(twoMacCloudKitDrill.contains("shasum -a 256"))
        #expect(twoMacCloudKitDrill.contains("run-peer.sh"))

        #expect(autonomyDrill.contains("AutonomyTrustLane"))
        #expect(autonomyDrill.contains("prepareRun"))
        #expect(autonomyDrill.contains("maxFilesChangedPerTask"))

        #expect(releaseCandidate.contains("ALLOW_XCODE_MANAGED_SIGNING"))
        #expect(releaseCandidate.contains("-allowProvisioningUpdates"))
        #expect(releaseCandidate.contains("Developer ID Application"))

        // Sprint O.3: notarization resume flags + runbook stay wired.
        #expect(releaseCandidate.contains("--notarize-only"))
        #expect(releaseCandidate.contains("--staple-only"))
        #expect(releaseCandidate.contains("--assess"))
        #expect(releaseCandidate.contains("--use-existing-package"))
        #expect(releaseCandidate.contains("--notary-runbook"))
        #expect(releaseCandidate.contains("Sprint O.3 — notarytool profile setup runbook"))
        #expect(releaseCandidate.contains("reuse_existing_package"))
        #expect(releaseCandidate.contains("assess_app"))

        #expect(visualRegression.contains("xcresult attachments are authoritative"))
        #expect(visualRegression.contains("testSprintLVisualRegressionSnapshotMatrix"))
        #expect(visualRegression.contains("testSprintNExpandedVisualRegressionSnapshotMatrix"))
        #expect(visualRegression.contains("testSprintOMaximizedWindowSnapshotMatrix"))
        #expect(visualRegression.contains("testSprintODarkAppearanceSnapshotMatrix"))
        #expect(visualRegression.contains("testSprintOLightAppearanceSnapshotMatrix"))
        #expect(visualRegression.contains("testSprintOProviderSetupEdgeCaseSnapshotMatrix"))
        #expect(visualRegression.contains("testSprintORunSheetSuccessFailureSnapshotMatrix"))
        #expect(visualRegression.contains("testSprintQ2RemediationVisualRegressionSnapshotMatrix"))
    }
}
