# Agenic Load-Balancer Release Readiness

Updated: May 22, 2026

## Release Lane

The current release lane is Developer ID / direct macOS distribution for a local developer tool. The app intentionally launches local CLI providers, reads user-selected workspaces, writes project coordination files, and stores only secret references in SwiftData/CloudKit. Do not switch to an App Store sandbox lane until the provider execution model has a separate sandbox-compatible design.

## Required Preflight

Run from the active iCloud checkout:

```sh
cd "/Users/zincoverde/Library/Mobile Documents/com~apple~CloudDocs/4_XcodeProjects/Agenic Load-Balancer"
script/release_preflight.sh
```

Use USB-backed build output for release build validation:

```sh
RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_Release_$(date +%Y%m%d_%H%M%S)" \
  script/release_preflight.sh --build
```

For a signed local build, omit the signing override:

```sh
RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_Release_Signed_$(date +%Y%m%d_%H%M%S)" \
  script/release_preflight.sh --build --signed-build
```

For a real release-candidate drill, use the credential-aware script. It never stores credentials in the repo; it expects the Developer ID certificate and notarytool profile to already live in the user's Keychain:

```sh
script/release_candidate.sh --verify-credentials

DEVELOPER_ID_IDENTITY="Developer ID Application: Example Team (TEAMID)" \
NOTARY_PROFILE="agenic-notary" \
RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_RC_$(date +%Y%m%d_%H%M%S)" \
  script/release_candidate.sh --all
```

If the certificate is missing, install a Developer ID Application certificate in Keychain Access or Xcode Accounts. If the notary profile is missing, create it with `xcrun notarytool store-credentials` using an app-specific password or App Store Connect API key, then rerun the credential check. Do not paste Apple account passwords, API keys, or app-specific passwords into planning docs.

If Xcode can manage the Developer ID certificate/provisioning profile even though `security find-identity` does not list a local private key, the release script can use Xcode-managed signing for archive/export:

```sh
ALLOW_XCODE_MANAGED_SIGNING=1 \
ALLOW_PROVISIONING_UPDATES=1 \
TEAM_ID="A45694H5ZG" \
RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_RC_$(date +%Y%m%d_%H%M%S)" \
  script/release_candidate.sh --archive --export --package
```

This still does not replace notarization credentials. `NOTARY_PROFILE` or `ALB_NOTARY_PROFILE` must name a `notarytool` keychain profile before `--notarize` or `--all` can complete.

### Resuming an already-signed run (Sprint O.3)

When `--all` or `--archive --export --package` has already produced a signed `Developer ID` ZIP under a USB run root, the notarize and staple steps can be picked up later — without re-archiving or re-signing — once a `notarytool` keychain profile is installed:

```sh
script/release_candidate.sh --notary-runbook
```

prints the full no-secret setup runbook (App Store Connect API key lane and Apple ID + app-specific password lane). Follow either lane locally, then resume notarization against the existing ZIP:

```sh
NOTARY_PROFILE="agenic-notary" \
RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_ReleaseManaged_20260525_121347" \
  script/release_candidate.sh --notarize-only --staple
```

`--notarize-only` reuses `RUN_ROOT/Packages/Agenic Load-Balancer.zip` instead of rebuilding it. `--staple-only` runs only `xcrun stapler staple` + `spctl` against the previously exported app. `--assess` runs only the Gatekeeper assessment when staple succeeded earlier. Apple account passwords, API keys, and app-specific passwords stay in Keychain and out of every commit, plan doc, and ledger entry.

## Entitlement Truth

- Bundle ID: `com.zincoverde.Agenic-Load-Balancer`
- App category: `public.app-category.developer-tools`
- Hardened Runtime: enabled in the Xcode target settings.
- iCloud container: `iCloud.com.zincoverde.Agenic-Load-Balancer`
- iCloud services: CloudKit and CloudDocuments.
- Ubiquity container and key-value store entitlements are present for project-level sync affordances.
- Push/remote notification entitlement posture is present for CloudKit remote-change observation.
- App Sandbox is not currently enabled. That is deliberate for the Developer ID lane because unrestricted local CLI orchestration is a core feature. If an App Store lane is introduced later, add a separate sandbox design for user-selected read/write files and provider execution instead of toggling sandbox on in this target.

## Signing And Notarization

Use Apple Developer documentation as the operational source of truth:

- Notarization overview: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Custom notarization workflow: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
- `notarytool`: `xcrun notarytool --help`
- `stapler`: `xcrun stapler --help`

Expected distribution flow:

```sh
xcodebuild archive \
  -project "Agenic Load-Balancer.xcodeproj" \
  -scheme "Agenic Load-Balancer" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -archivePath "$RUN_ROOT/Archives/Agenic Load-Balancer.xcarchive"
```

Then export, notarize the distributable artifact with `xcrun notarytool submit --wait`, staple with `xcrun stapler staple`, and verify with `spctl -a -vv`.

The repo-owned release-candidate script performs that sequence as:

1. Signed archive with `xcodebuild archive`.
2. Developer ID export with `xcodebuild -exportArchive`.
3. ZIP packaging with `ditto --keepParent`.
4. Notary submission with `xcrun notarytool submit --wait`.
5. Staple and Gatekeeper assessment with `xcrun stapler staple` and `spctl -a -vv --type execute`.

## Privacy And Data Handling

- SwiftData is the local master repository.
- CloudKit/private iCloud sync carries project metadata, provider setup state, routing decisions, usage metrics, run outcomes, coordination events, snapshots, autonomy plans/tasks, conflict records, validation gates, and audit trail records.
- Keychain stores provider API keys or secret values. SwiftData and CloudKit store references only.
- Prompt/output excerpts and transcript summaries may be stored for routing and restore workflows. Full project files are not synced unless a future feature explicitly adds that behavior.
- Local CLI providers may read and write files inside user-approved workspaces according to per-app and per-project policy settings.
- Validation and build artifacts should stay on `/Volumes/USB256/Xcode_Projects_Storage/` or another explicit scratch root, never in stale OneDrive paths.

## Migration And Restore Gates

- `AgenicDataModel.models` and `ModelKey.renderOrder` must stay in sync.
- Snapshot archives must include every SwiftData model family that needs backup/restore continuity.
- Additive model fields must decode from older archives with defaults or optionals.
- Before release, run focused `SnapshotPipelineTests` and the release-readiness tests.
- Do not increment `SnapshotArchiveSchema.currentVersion` unless older archives genuinely cannot be decoded.

## Rollback Plan

1. Keep the previous signed/notarized artifact and its commit SHA.
2. Before installing a new release, create an app snapshot from Restore.
3. On failure, quit the new app, reinstall the previous artifact, and use Restore preview before applying any snapshot.
4. If CloudKit records diverge across machines, use Conflicts first, then restore into a new local copy before destructive replace.
5. Record the rollback commit, artifact, snapshot checksum, and conflict decisions in `AgentNotes.md`.
