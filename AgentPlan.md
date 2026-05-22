# AgentPlan.md - Agenic Load-Balancer Comprehensive Implementation Plan

Updated: May 22, 2026

## Active Source Truth

- Active working path: `/Users/zincoverde/Library/Mobile Documents/com~apple~CloudDocs/4_XcodeProjects/Agenic Load-Balancer`.
- Active branch: `main`.
- Active remote: `origin`.
- USB scratch policy: derived data, result bundles, temporary validation roots, and plan backups should live under `/Volumes/USB256/Xcode_Projects_Storage/`.
- Stale checkout policy: do not write new data to `/Users/zincoverde/Library/CloudStorage/OneDrive-Personal/4_XcodeProjects/Agenic Load-Balancer`.
- Archive migration policy: `/Users/zincoverde/Documents/OneDrive-OLD/4_XcodeProjects/Agenic Load-Balancer` may be read only when missing historical material must be migrated. Do not create, edit, or checkpoint new work there.
- Repo-visible status files: `AgentPlan.md` is the implementation plan, `PLAN.md` is the product/architecture handoff, and `AgentNotes.md` is the coordination ledger projection.
- SwiftData remains the app's canonical local repository; CloudKit is private sync/backup transport; secrets remain Keychain-only.

## Current Queue Answer

- The previously reported iCloud reality gap is resolved. The iCloud checkout was fast-forwarded from the earlier Phase 7.2-era state to the pushed Phase 7.3-7.6 implementation history on `origin/main`.
- The implementation commits now present in the active iCloud checkout include the command bar, intelligent AgentNotes preflight, Foundation Models routing tie-breaker, autonomous project manager foundation, autonomy persistence/execution wiring, dispatch hardening, UI and project settings repair, cancelled coordination cleanup, provider auth/settings/workspace task wiring, autonomy readiness polish, and settings tool alignment.
- Sprint B from this roadmap is implemented as an in-app Foundation Models diagnostics route. Settings > Agents can check host availability and run live command-bar metrics, run-summary, and routing tie-break probes while keeping deterministic fallback behavior intact.
- Sprint C from this roadmap is implemented as provider-neutral token budget and continuation hardening. Prompt Router approvals now show context pressure, oversized AgentNotes preflight context is compacted before dispatch, run outcomes retain context-budget and continuation metadata, long stdout/stderr transcripts are segmented for durable storage/snapshots, and context-window failures prepare a safe follow-up prompt instead of only reporting the failure.
- Sprint D from this roadmap is implemented as provider probe normalization and routing telemetry hardening. Provider probes now report auth and limit state with normalized labels, routing and command-bar actions consume recent reliability snapshots, and the dashboard/router continue to filter to configured providers by default.
- Sprint E from this roadmap is implemented as the first Cross-Machine Conflict Center slice. The app now has a dedicated Conflicts navigation surface that previews persisted conflict records and synthetic operation-log divergence, shows local/remote envelopes, peer/snapshot warnings, dry-run resolution choices, rollback anchors, and records explicit decisions into SwiftData without mutating target entities.
- Sprint F from this roadmap is implemented as trusted autopilot lane templates and safety review. Autonomy now has explicit read-only review, plan-only, test-only, docs-only edits, small-file edits, dependency-update, and commit/push lanes with root scopes, protected paths, command allowlists, network posture, budget caps, validation commands, rollback-evidence checks, and a visible "why this is safe" review before task preparation.
- Sprint G from this roadmap is implemented as the first automated UI flow and launch-verification slice. UI tests now cover the minimum-window Command Bar, Prompt Router, Settings Tools controls, Projects controls, project settings, workspace/task navigation, Restore, Autonomy, and light/dark launch flows using deterministic `--uitesting` fixtures and stable accessibility identifiers.
- Future work remains, but it should be treated as scoped roadmap work after Sprint G rather than unfinished Phase 7.3-7.6 implementation.

## What Is 100 Percent Implemented In The Active Tree

- macOS SwiftUI app shell with Liquid Glass-inspired navigation, dashboard, prompt router, providers, projects, restore, AgentNotes, autonomy, history, and in-app settings surfaces.
- SwiftData schema for projects, provider profiles, command profiles, usage snapshots, routing decisions, run outcomes, coordination events, snapshots, autonomy goals/plans/tasks, policies, machine peers, validation gates, conflict records, and audit trail entries.
- CloudKit/private iCloud configuration for SwiftData sync and app-level sync status display.
- Keychain reference model for secrets, with SwiftData/CloudKit storing references and setup metadata only.
- Provider catalog and setup wizard with install instructions, account/browser login lanes, API-key lanes, verification commands, auth probes, docs links, custom command profiles, and environment hints.
- Prompt Router scoring, rationale cards, score breakdowns, configured-provider filtering, quota/cost/performance inputs, accuracy history, recent reliability history, and close-score tie-break hooks.
- Approval-gated run pipeline with live console, process streaming, cancellation, token usage capture, preprocessing timing, context-window failure detection, summary status, outcome rating, and optional git checkpointing.
- Codex CLI prompt transport through stdin (`codex exec --json --cd <project> -`) so long prompts are not rejected as command-line arguments.
- Run-state truth fixes so context-window overflow, provider structured failure status, nested nonzero exit codes, quota/rate-limit signals, and cancellation are represented honestly.
- Snapshot and restore center with preview, restore safety, checksums, record counts, and SwiftData-backed archive DTOs.
- Dashboard heatmap and performance views using only configured providers, including recent reliability.
- Projects view with add/edit/delete, per-workspace settings, persisted folder metadata, prompt excerpt sync, AgentNotes regeneration, and nested task/workspace navigation.
- In-app Settings sheet with editable generation, context, tools, agents, server, memory, storage, and about surfaces.
- Tool permission defaults for tool calling, shell tools, network search, filesystem writes, mutating-command approval, default working path, default temporary path, context compaction, and summary caps.
- Provider-neutral token budgeting, preflight AgentNotes compaction, durable transcript segment storage, snapshot round-trip support for transcript segments, and continuation prompts for context-window failures.
- AgentNotes coordination with NSFileCoordinator-backed reads/writes, preflight prompt injection, active-conflict filtering, reconciliation, stale dispatch cleanup, and regenerated ledger projection.
- First-class `cancelled` coordination status so harmless cancelled runs no longer appear as active blockers.
- Cross-Machine Conflict Center with local/remote operation-envelope previews, affected field counts, audit link extraction, stale peer warnings, snapshot rollback warnings, keep-local/accept-remote/merge/restore dry-run actions, and persisted resolution records.
- Trusted autopilot lane templates for read-only review, plan-only, test-only, docs-only edits, small-file edits, dependency updates, and commit/push checkpoints, including command allowlists, write allowlists, network policy, cost/file caps, validation gates, rollback-evidence requirements, and compatibility-safe policy JSON encoding.
- Autonomy safety review UI that shows the selected lane, latest snapshot/checkpoint evidence, validation gate, per-task decision, and "why this is safe" reasoning before an approval-gated run can be prepared.
- Phase 7.1 Foundation Models in-process runner adapter and availability-gated streaming path.
- Phase 7.2 structured run summary support using framework-independent values plus live Foundation Models implementation behind availability gates.
- Phase 7.3 natural-language tool-calling command bar with rank, dispatch draft, provider probe, snapshot draft, AgentNotes reconcile, and dashboard metrics actions.
- Phase 7.4 intelligent AgentNotes preflight and AI-assisted reconciliation proposal surface, with final writes still confirmation-gated.
- Phase 7.5 Foundation Models routing tie-breaker for close provider scores while deterministic routing remains canonical.
- Phase 7.6 autonomous project management foundation with policy levels, safety checks, deterministic goal planning, persisted plans/tasks, validation commands, audit trail, machine sync health, and conflict-resolution primitives.
- Autonomy readiness control room with safety contract checklist, readiness score, persisted queue, validation metrics, and peer sync posture.
- Safety audit tests proving unavailable Foundation Models paths degrade to no-op/fallback behavior and mutating command-bar actions return draft/approval-required results.
- Foundation Models diagnostics runner and Settings > Agents diagnostics UI that probe availability, command-bar metrics, post-run summaries, and close-score routing tie-breaks without blocking deterministic app behavior.

## What Is Partial Or Needs Live-System Validation

- Live Foundation Models happy path now has an explicit in-app diagnostics route, but it still needs periodic observation on macOS 26.x machines where Apple Intelligence and Foundation Models are actually available. Tests cover scripted/fallback paths and the diagnostics control flow, not every live model behavior.
- CloudKit sync is wired, status is observable, and Sprint E exposes a conflict inspection/resolution surface. "Perfect cross-machine sync" still needs repeated multi-device, multi-account, network-failure, and conflict-injection validation before it can be described as production-proven.
- Provider auth recipes are grounded in official flows and expose account/API-key lanes, but each provider's live login, subscription state, quota endpoint, and CLI behavior can change and needs recurring probe maintenance.
- Context compaction now covers pre-dispatch AgentNotes pressure and run telemetry, and context-window failures now create continuation prompts. A full autonomous continuation loop still needs provider-specific resume execution policies and richer source-file summarization before the app can safely continue long work without approval.
- Autonomy now has trusted-lane policy templates and per-task safety reviews. It remains deliberately bounded: arbitrary repo mutation, multi-step unattended execution, and recovery still require future live validation and explicit approval boundaries.
- UI validation now has launch coverage, minimum-window flow coverage, and a first deterministic workspace/task flow. Screenshot-diff baselines, maximized/full-screen matrices, provider setup edge cases, and run-sheet failure-state permutations still need broader automated coverage.
- Conflict resolution now has deterministic primitives, audit records, and a user-facing dry-run Conflict Center. The remaining "perfect conflict resolution" promise needs live cross-machine recovery drills, richer merge-domain policies for each entity type, and end-to-end restore-into-copy workflows.

## Deferred Future Queue

- Live Foundation Models smoke suite: run command bar, run summary, AgentNotes intelligence, and tie-breaker against real on-device Foundation Models and record observed availability states.
- Provider-specific continuation loops: add source-file summarization, provider-specific context windows, bounded resume execution policies, and continuation approval flows that can safely chain long runs without losing auditability.
- Provider-specific live probe maintenance: expand the normalized Sprint D probe layer with per-provider quota endpoints, subscription freshness checks, version drift detection, and recurring live auth/login validation.
- Cross-machine sync validation: run two or more machines against the same CloudKit container, verify workspace/task history propagation, inject concurrent edits, and document exact conflict outcomes.
- Conflict resolution expansion: add entity-specific merge policies, execute real restore-into-copy workflows, and run multi-device recovery drills with intentionally divergent CloudKit records.
- Trusted-autopilot expansion: build on the new Sprint F lane templates with richer live evidence collection, automatic snapshot creation, bounded multi-step execution, and per-lane recovery drills.
- Autonomous loop scheduler: persist goals, break them into bounded sprints, run validation gates, checkpoint results, ask for approvals at risk boundaries, and stop on uncertainty.
- Provider setup UX: add status badges for account login freshness, API-key reference health, missing binary remediation, and per-provider docs snapshots.
- Visual regression coverage: capture resized window, full screen, command bar, settings, projects/workspace task tree, providers, restore, and autonomy views across light/dark appearances.
- Packaging and release: finalize signing, entitlements, notarization, onboarding, privacy copy, crash/log policy, and upgrade/migration tests.

## Safety Principles

- Never run installers silently.
- Never store API keys, OAuth refresh material, or raw secrets in SwiftData or CloudKit.
- Never write outside approved roots without an explicit policy decision and user approval.
- Never treat a cancelled run as blocked work.
- Never call a run successful when the provider output says context overflow, quota failure, structured failure, or nested nonzero exit.
- Never mutate AgentNotes or project files from an AI suggestion without a user-visible preview and approval.
- Never let Foundation Models availability be a hard requirement for core app behavior.
- Never replace deterministic routing math with model reasoning; model reasoning may only explain or break ties inside a bounded candidate set.

## Architecture Map

### Data And Persistence

- `AgenicDataModel.models` registers all SwiftData entities required by the app, including provider, routing, run, coordination, snapshot, and autonomy records.
- `AgenicRepository` owns local/CloudKit model container creation.
- `AgenicLaunchEnvironment.usesVolatileStore(...)` protects unit/UI tests from accidentally initializing the CloudKit-backed persistent store.
- App settings live in `@AppStorage` for global defaults and SwiftData project/workspace fields for workspace-specific overrides.
- Snapshots use DTOs to preserve compatibility with older archives and to keep restore previews separate from destructive writes.

### Providers And Auth

- `ProviderCatalog` defines provider identity, capabilities, setup guidance, command defaults, auth expectations, and execution modes.
- `ProviderAuthRecipe` separates account/browser login, API-key, environment variable, and direct OAuth-style setup affordances.
- `ProviderSetupWizard` prepares safe install/auth/profile/verify steps and stores only Keychain references for secrets.
- `AgentCLIAdapter` and related adapter factories provide availability, version, auth, command building, stream parsing, and cancellation surfaces.

### Routing And Dispatch

- `RoutingEngine` remains the deterministic scoring source.
- `RoutingRecommendationCoordinator` wraps deterministic rankings with optional close-score tie-break decisions.
- `RunDispatcher` composes prompts, applies workspace policies, dispatches through child process or in-process Foundation Models runners, streams output, records usage, detects failures, summarizes successful runs, updates coordination events, and optionally checkpoints via git.
- `AgentProcessRunner` owns subprocess lifecycle, stdin writing, event streaming, termination, and cancellation.

### AgentNotes And Coordination

- `ProjectCoordinationActor` coordinates AgentNotes reads/writes, reconciliation, excerpts, full reads, active-status filtering, stale dispatch cleanup, and SwiftData ledger projection.
- AgentNotes preflight gathers relevant active claims and ignores completed/checkpointed/cancelled history.
- AI-assisted reconciliation proposes merges but leaves final writes behind explicit confirmation.

### Command Bar

- `CommandBarActionExecutor` wraps app actions for rank, dispatch draft, probe, snapshot draft, reconcile, and metrics.
- `CommandBarTools` exposes Foundation Models `Tool` wrappers behind compile-time and availability gates.
- `NaturalLanguageCommandBarModel` runs the live tool-calling session when available and falls back to deterministic parsing/actions when Foundation Models are unavailable.
- Mutating actions return approval drafts, not silent execution.

### Autonomy

- `AutonomyPolicy` defines execution levels and default guardrails.
- `AutonomyPolicyEvaluator` decides whether each proposed task is allowed, approval-required, or blocked.
- `AutonomousProjectManager` converts goals into deterministic inspect/plan/execute/validate/checkpoint task plans.
- `AutonomyPersistence` stores goal, plan, task, policy, operation, validation, and audit records.
- `AutonomyReadinessBuilder` scores readiness before autonomous work is prepared.
- `ConflictResolutionEngine`, `ConflictResolutionPreviewBuilder`, `ConflictCenterView`, and `MachineSyncCoordinator` provide deterministic conflict previews, decision records, and peer-health warnings.

## Implementation Roadmap

### Sprint A - Canonical iCloud Root And Handoff Truth

Status: completed in this checkpoint.

- Confirm the active checkout is `/Users/zincoverde/Library/Mobile Documents/com~apple~CloudDocs/4_XcodeProjects/Agenic Load-Balancer`.
- Fast-forward the iCloud checkout to the pushed Phase 7.3-7.6 implementation history.
- Preserve local project metadata and entitlements that strengthen app icon, developer-tool category, iCloud container, CloudDocuments, and ubiquity key-value store posture.
- Update `AgentPlan.md`, `PLAN.md`, and `AgentNotes.md` so no handoff points at stale OneDrive as the writable root.
- Validated with derived data and intermediates on `/Volumes/USB256/Xcode_Projects_Storage/`.
- Commit and push this canonical-root checkpoint.

### Sprint B - Live Foundation Models Verification

Status: implemented in this checkpoint. Live success still depends on the host reporting `SystemLanguageModel.default.availability` as available.

Goal: prove the live on-device paths behave in the real host environment, not only through scripted tests.

- Added a Settings > Agents Foundation Models Diagnostics section that checks `SystemLanguageModel.default.availability`.
- Added a diagnostics runner that can execute command-bar metrics through the live command-bar Foundation Models path.
- Added a run-summary probe through the live `RunSummarizing` factory.
- Added a close-score routing tie-break probe through the live `RoutingTieBreaking` factory.
- Captured availability, skipped, failed, unsupported-locale/language, refusal/safety, context-window, and successful states as explicit probe results.
- Recorded implementation and validation results in `AgentNotes.md` and `PLAN.md`.

Acceptance:

- Live paths succeed or degrade gracefully with explicit user-readable status.
- No live Foundation Models failure blocks deterministic routing, run dispatch, AgentNotes reconciliation, or dashboard behavior.

Validation:

- Swift Testing reported `Test run with 141 tests in 21 suites passed after 3.001 seconds` during the full-scheme run, including the new Foundation Models diagnostics suite, before the UI-test wrapper later hung and was terminated.
- Clean build-only validation with isolated USB-derived roots returned `** BUILD SUCCEEDED **` using `/Volumes/USB256/Xcode_Projects_Storage/AgenicLoadBalancer/Build-20260521232102`.
- Follow-up live observation remains: collect real available-host, refusal/safety, unsupported-locale, disabled-Apple-Intelligence, and success snapshots from machines as those states occur.

### Sprint C - Token Budget And Continuation Hardening

Status: implemented in this checkpoint.

Goal: make long runs efficient and resumable instead of merely detecting context overflow after a provider fails.

- Added a provider-neutral `TokenBudgetEstimator` with provider-specific context-window overrides and configurable thresholds.
- Estimate prompt, AgentNotes, workspace policy, project path, stdout, stderr, cached, output, and reasoning token pressure before and after dispatch.
- Compact AgentNotes preflight context before provider dispatch when the estimated prompt exceeds the configured threshold.
- Chunk stdout/stderr transcripts into durable `RunTranscriptSegmentRecord` rows and snapshot DTOs.
- Store context-budget summaries, continuation summaries, and continuation prompts on run outcomes.
- Add approval-sheet warnings for high-context runs before the user approves dispatch.
- Add outcome-sheet continuation UI with copyable follow-up prompt when a provider reports context-window overflow.

Acceptance:

- Oversized AgentNotes preflight context is reduced before provider dispatch when possible.
- Context-window failures remain visible as failures, but the app offers a safe continuation plan.
- Long transcripts survive as segmented records that can be restored through snapshots.

Validation:

- Focused Sprint C tests passed on May 22, 2026 with isolated USB roots: `xcodebuild test -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS,arch=arm64" -derivedDataPath "/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintC_20260522_003925/DerivedData" -resultBundlePath "/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintC_20260522_003925/Results/SprintC_Focused.xcresult" ... -only-testing:"Agenic Load-BalancerTests/TokenBudgetTests" -only-testing:"Agenic Load-BalancerTests/RunPipelineTests"` returned `** TEST SUCCEEDED **`.
- Full app build validation passed on May 22, 2026 with isolated USB roots under `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintC_Build_20260522_010506`, returning `** BUILD SUCCEEDED **`.

### Sprint D - Provider Probe And Routing Telemetry Hardening

Status: implemented in this checkpoint. Live provider-specific probe expansion remains a maintenance queue item because CLI auth/quota surfaces can change outside the app.

Goal: make routing quality reflect live provider state and recent reliability.

- Added normalized provider probe auth states for account signed in, API key present, custom profile, unauthenticated, not required, and unknown.
- Added normalized limit states for healthy, subscription-limited, quota-limited, rate-limited, context-limited, and unknown output.
- Added recent provider reliability snapshots from completed run outcomes, including succeeded, failed, cancelled, quota-limited, rate-limited, and context-limited signals.
- Fed recent reliability into `RoutingEngine`, command-bar rank/dispatch actions, autonomy run preparation, Foundation Models tie-break context, approval-sheet score breakdowns, routing rationale cards, and dashboard heatmap cells.
- Kept dashboard and Prompt Router recommendations filtered to configured providers by default.
- Added focused regression coverage for normalized probe classification, recent reliability scoring, routing reliability weighting, and the reliability dashboard metric.

Acceptance:

- The dashboard and router show only configured providers by default.
- Provider recommendations explain live availability, capability fit, limit pressure, accuracy, speed, cost, and recent reliability.

Validation:

- `git diff --check` produced no output.
- Build-only validation passed from the active iCloud root with isolated Sprint D USB roots: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS,arch=arm64" -derivedDataPath "/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintD_20260522_032017/DerivedData_BuildOnly" ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -skipMacroValidation` returned `** BUILD SUCCEEDED **`.
- App launch verification passed with `DERIVED_DATA_PATH="/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintD_20260522_032017/DerivedData_RunVerify" CODE_SIGNING_ALLOWED=NO ./script/build_and_run.sh --verify`.
- Two focused `xcodebuild test` attempts for the new Sprint D coverage were interrupted after Xcode test orchestration stalled before a visible `xctest` child appeared; this is recorded as a validation harness issue, not as a passing test claim.

### Sprint E - Cross-Machine Conflict Center

Status: implemented in this checkpoint as the first inspectable/reversible conflict center slice. Live multi-machine recovery drills remain future validation work.

Goal: make CloudKit sync and multi-machine coordination inspectable and reversible.

- Added an operation-envelope inspector for persisted `ConflictResolutionRecord` rows and synthetic divergent `AutonomyOperationRecord` pairs.
- Shows local/remote machine IDs, operation kinds, Lamport clocks, timestamps, affected entity/field counts, source run/task/plan links, and proposed deterministic outcomes.
- Added conflict dry-run actions for keep local, accept remote, merge, restore snapshot, and restore into new copy.
- Persisted user decisions as `ConflictResolutionDecision` JSON on `ConflictResolutionRecord`; target entities remain untouched by this first slice.
- Synthetic operation-log conflicts now create a backing conflict record before the selected decision is saved.
- Added stale peer warnings through `MachineSyncCoordinator` and snapshot rollback warnings when no rollback anchor exists.
- Wired the dedicated Conflicts item into the Configure sidebar.
- Added focused tests for record preview decoding, synthetic divergence previewing, synthetic conflict record creation, decision persistence, and stale peer warning display.

Acceptance:

- Users can understand and resolve conflicts without guessing which machine changed what.
- Every destructive conflict action has a preview and rollback path.

Validation:

- `git diff --check` produced no output.
- App build passed with USB-derived data under `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintE_20260522_083200`, returning `** BUILD SUCCEEDED **`.
- Focused conflict tests passed with `xcodebuild ... -only-testing:"Agenic Load-BalancerTests/ConflictResolutionEngineTests"`; result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintE_20260522_083200/Logs/Test/Test-Agenic Load-Balancer-2026.05.22_08-56-05--0400.xcresult`.
- Automated UI launch test passed after pinning the destination to `platform=macOS,arch=arm64`; result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintE_20260522_083200/Logs/Test/Test-Agenic Load-Balancer-2026.05.22_08-57-43--0400.xcresult`.
- Direct launch smoke check kept the freshly built app alive under `--uitesting` for 8 seconds.

### Sprint F - Trusted Autopilot Lanes

Status: implemented in this checkpoint as the policy-template and safety-review slice. Fully unattended multi-step execution remains Sprint F/G follow-up work.

Goal: make autonomy feel inevitable, safe, and beautiful without skipping safety boundaries.

- Added scoped trust lanes for read-only review, plan-only, test-only, docs-only edits, small-file edits, dependency updates, and commit/push checkpoints.
- Added per-workspace policy templates with explicit allowed roots, protected paths, write allowlists, command allowlists, network policy, budget caps, max changed-file caps, and validation gate commands.
- Require a successful snapshot or git checkpoint before mutation lanes can prepare implementation/repair/commit runs; dependency-update lanes require a snapshot specifically.
- Added command allowlist enforcement for validation gates and policy review.
- Added compatibility-safe decoding for previously persisted policy JSON so existing `AutonomyPolicyRecord` rows remain readable.
- Added an Autonomy screen lane picker, rollback evidence badges, selected validation gate, per-task safety decision, and "why this is safe" reasoning before each approval-gated run preparation.
- Kept execution one bounded task at a time through the existing approval sheet; unattended multi-task loops remain deliberately deferred.

Acceptance:

- The user can say a goal, choose a bounded trust lane, see a scoped plan, and review safety reasons before approving a run.
- The app stops safely when lane, rollback evidence, command allowlist, protected path, network, budget, or file-count policy becomes uncertain.

Validation:

- `git diff --check` produced no output before validation.
- Build validation passed with USB roots under `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintF_20260522_093004`, returning `** BUILD SUCCEEDED **`.
- Focused Sprint F policy/manager tests passed with `xcodebuild ... -only-testing:"Agenic Load-BalancerTests/AutonomyPolicyTests" -only-testing:"Agenic Load-BalancerTests/AutonomousProjectManagerTests"`; result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintF_20260522_093004/Results/SprintF_Focused.xcresult`.
- Automated UI launch validation passed in light and dark appearances; result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintF_20260522_093004/Results/SprintF_UILaunch.xcresult`.

### Sprint G - UI Flow And Visual Regression Coverage

Status: implemented in this checkpoint as the first automated UI flow and launch-verification slice. Expanded screenshot-diff baselines remain a future visual-regression queue item.

Goal: keep the Liquid Glass experience aligned, calm, and robust across window sizes.

- Added volatile `--uitesting` fixture bootstrap so UI tests launch with configured providers, sample workspaces, active/cancelled coordination records, a succeeded run outcome, autonomy records, snapshot data, and machine-peer sync state without touching CloudKit production data.
- Added stable accessibility identifiers for toolbar actions, Command Bar controls, Prompt Router, Settings Tools toggles, Projects controls, project settings, workspace/task navigation, Restore, Autonomy, and launch smoke surfaces.
- Replaced fragile nested sidebar `Button` navigation for workspaces/tasks with selection-bound `NavigationLink` rows so clicking nested workspace/task items actually changes app selection.
- Added a minimum-window UI flow that opens/closes the Command Bar, verifies Prompt Router controls, opens Settings, and checks the aligned Tools permission toggles.
- Added a workspace UI flow that exercises Projects controls, project settings, workspace/task detail navigation, Restore, and Autonomy readiness surfaces.
- Added a launch UI test that verifies dashboard launch in light and dark appearances, with a Command-N fallback for macOS window-restoration edge cases.
- Kept screenshot artifacts attached to the UI-test result bundles; formal pixel-diff thresholds remain deferred to the broader visual-regression matrix.

Acceptance:

- Regression tests catch the UI failures reported in the screenshot-driven repair turns.
- Settings and project/workspace controls remain editable and aligned at non-maximized sizes.

Validation:

- `git diff --check` produced no output before the final Sprint G closeout.
- Focused Sprint G UI flow tests passed with result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintG_20260522_105504/Results/SprintG_UIFlows_Final.xcresult`.
- Automated launch validation passed in light and dark appearances with result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintG_20260522_105504/Results/SprintG_LaunchProbe_Final.xcresult`.
- Final app build passed with isolated USB roots under `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintG_20260522_105504`, returning `** BUILD SUCCEEDED **`.

### Sprint H - Packaging, Entitlements, And Release Readiness

Goal: turn the developer tool into a durable macOS app distribution.

- Confirmed the active release lane is Developer ID / direct macOS distribution for a local developer tool. App Sandbox remains intentionally disabled until provider execution has a separate sandbox-compatible design.
- Added `ReleaseReadiness.md` with the release lane, entitlement truth, signing/notarization references, privacy/data handling notes, migration/restore gates, and rollback plan.
- Added `script/release_preflight.sh` to validate build settings, entitlements, release documentation, required Apple tooling, and optional Release build/archive flows with USB-backed build output.
- Added release-readiness regression tests that lock the bundle ID, Hardened Runtime, app category, CloudKit/CloudDocuments entitlements, version settings, release checklist, and preflight script wiring.
- Expanded snapshot archive/restore coverage so Phase 7.6 provider command profiles, autonomy goals/plans/tasks/policies, machine peers, operation logs, conflict records, validation gates, and audit trail records are included in payload counts, identifiers, replace, merge, and schema-order tests.
- Kept secrets in Keychain-only references and documented CloudKit sync contents for project metadata, provider setup state, routing decisions, usage metrics, run outcomes, coordination events, snapshots, autonomy records, conflict records, validation gates, and audit trails.

Acceptance:

- Build, archive, sign, and install flows are documented and guarded by a repeatable preflight.
- Users understand what syncs to iCloud, what remains local, and what actions require approval.
- Snapshot restore remains migration-ready for all registered SwiftData model families.

Validation:

- `script/release_preflight.sh` passed after checking project settings, entitlements, release documentation, and required tools.
- Focused Sprint H tests passed with isolated USB roots: `ReleaseReadinessTests` and `SnapshotPipelineTests`; result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintH_20260522_141338/Results/SprintH_Focused4.xcresult`.
- `RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintH_20260522_141338/ReleasePreflight" script/release_preflight.sh --build` returned `** BUILD SUCCEEDED **` and verified the built app bundle identifier.
- `git diff --check` produced no output before the final Sprint H closeout.

## Validation Commands

Use the active iCloud root:

```sh
cd "/Users/zincoverde/Library/Mobile Documents/com~apple~CloudDocs/4_XcodeProjects/Agenic Load-Balancer"
```

Use USB-backed build products:

```sh
RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_iCloud_$(date +%Y%m%d_%H%M%S)"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project "Agenic Load-Balancer.xcodeproj" \
  -scheme "Agenic Load-Balancer" \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$RUN_ROOT/DerivedData" \
  SYMROOT="$RUN_ROOT/Build" \
  OBJROOT="$RUN_ROOT/Intermediates" \
  SHARED_PRECOMPS_DIR="$RUN_ROOT/PrecompiledHeaders" \
  CODE_SIGNING_ALLOWED=NO \
  test
```

For launch verification:

```sh
./script/build_and_run.sh --verify
```

For lightweight document/checkpoint validation:

```sh
git diff --check
git status --short --branch
```

## Commit And Push Rules

- Commit and push after every phase, wave, sprint, step, or other codebase change.
- Each commit message must explain the user-visible reason for the checkpoint.
- Never commit derived data, result bundles, local temp files, secrets, or stale checkout artifacts.
- Preserve unrelated user changes; do not revert files unless the user explicitly asks.
- After pushing, record the commit in `AgentNotes.md` or `PLAN.md` when it changes handoff truth.

## Next Recommended Implementation Unit

After this Sprint H checkpoint is pushed, the remaining queue is mostly live-system maturity rather than missing Phase 7.3-7.6 feature wiring: provider-specific live probe maintenance, live multi-machine conflict recovery drills, signed Developer ID archive/notarization with real credentials, and expanded screenshot-diff visual regression. The next useful implementation sprint is a release-candidate drill that runs signed archive/export/notarization on the user's chosen distribution credentials and records the artifact/rollback evidence.
