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
