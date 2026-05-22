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
- Future work remains, but it should be treated as the next scoped roadmap work, starting with Sprint D provider probe and routing telemetry hardening rather than unfinished Phase 7.3-7.6 implementation.

## What Is 100 Percent Implemented In The Active Tree

- macOS SwiftUI app shell with Liquid Glass-inspired navigation, dashboard, prompt router, providers, projects, restore, AgentNotes, autonomy, history, and in-app settings surfaces.
- SwiftData schema for projects, provider profiles, command profiles, usage snapshots, routing decisions, run outcomes, coordination events, snapshots, autonomy goals/plans/tasks, policies, machine peers, validation gates, conflict records, and audit trail entries.
- CloudKit/private iCloud configuration for SwiftData sync and app-level sync status display.
- Keychain reference model for secrets, with SwiftData/CloudKit storing references and setup metadata only.
- Provider catalog and setup wizard with install instructions, account/browser login lanes, API-key lanes, verification commands, auth probes, docs links, custom command profiles, and environment hints.
- Prompt Router scoring, rationale cards, score breakdowns, configured-provider filtering, quota/cost/performance inputs, accuracy history, and close-score tie-break hooks.
- Approval-gated run pipeline with live console, process streaming, cancellation, token usage capture, preprocessing timing, context-window failure detection, summary status, outcome rating, and optional git checkpointing.
- Codex CLI prompt transport through stdin (`codex exec --json --cd <project> -`) so long prompts are not rejected as command-line arguments.
- Run-state truth fixes so context-window overflow, provider structured failure status, nested nonzero exit codes, quota/rate-limit signals, and cancellation are represented honestly.
- Snapshot and restore center with preview, restore safety, checksums, record counts, and SwiftData-backed archive DTOs.
- Dashboard heatmap and performance views using only configured providers.
- Projects view with add/edit/delete, per-workspace settings, persisted folder metadata, prompt excerpt sync, AgentNotes regeneration, and nested task/workspace navigation.
- In-app Settings sheet with editable generation, context, tools, agents, server, memory, storage, and about surfaces.
- Tool permission defaults for tool calling, shell tools, network search, filesystem writes, mutating-command approval, default working path, default temporary path, context compaction, and summary caps.
- Provider-neutral token budgeting, preflight AgentNotes compaction, durable transcript segment storage, snapshot round-trip support for transcript segments, and continuation prompts for context-window failures.
- AgentNotes coordination with NSFileCoordinator-backed reads/writes, preflight prompt injection, active-conflict filtering, reconciliation, stale dispatch cleanup, and regenerated ledger projection.
- First-class `cancelled` coordination status so harmless cancelled runs no longer appear as active blockers.
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
- CloudKit sync is wired and status is observable, but "perfect cross-machine sync" needs repeated multi-device, multi-account, network-failure, and conflict-injection validation before it can be described as production-proven.
- Provider auth recipes are grounded in official flows and expose account/API-key lanes, but each provider's live login, subscription state, quota endpoint, and CLI behavior can change and needs recurring probe maintenance.
- Context compaction now covers pre-dispatch AgentNotes pressure and run telemetry, and context-window failures now create continuation prompts. A full autonomous continuation loop still needs provider-specific resume execution policies and richer source-file summarization before the app can safely continue long work without approval.
- Autonomy is deliberately approval-gated and policy-aware. It is not yet a fully trusted autopilot that can safely perform arbitrary repo mutation, validation, commit, push, and recovery without user approval.
- UI validation has launch and full-scheme coverage, but screenshot-level visual regression, resized-window flows, settings subpanes, provider setup edge cases, and run-sheet failure states need broader automated coverage.
- Conflict resolution has deterministic primitives and audit records, but the user-facing "perfect conflict resolution" promise still needs richer conflict visualization, dry-run previews, reversible operation envelopes, and recovery drills.

## Deferred Future Queue

- Live Foundation Models smoke suite: run command bar, run summary, AgentNotes intelligence, and tie-breaker against real on-device Foundation Models and record observed availability states.
- Provider-specific continuation loops: add source-file summarization, provider-specific context windows, bounded resume execution policies, and continuation approval flows that can safely chain long runs without losing auditability.
- Provider probe hardening: add real auth/quota/version probes for each configured provider, normalize failures, and feed trendline reliability back into routing.
- Cross-machine sync validation: run two or more machines against the same CloudKit container, verify workspace/task history propagation, inject concurrent edits, and document exact conflict outcomes.
- Conflict center UI: expose operation envelopes, divergent records, proposed merges, rollback options, and "restore into new local copy" flows in a dedicated inspector.
- Trusted-autopilot lanes: define a staged path from observe-only to plan-only to proposed-action to approved-execution to tightly bounded trusted automation.
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
- `ConflictResolutionEngine` and `MachineSyncCoordinator` provide deterministic conflict and peer-health primitives.

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

Goal: make routing quality reflect live provider state and recent reliability.

- Add per-provider auth probes that distinguish installed, account-signed-in, API-key-present, subscription-limited, quota-limited, and unknown.
- Parse provider-specific token/quota/rate-limit output into normalized usage pressure.
- Add reliability trendlines from recent runs, cancellations, failures, and user accuracy ratings.
- Feed trendline reliability into `RoutingEngine` with explainable score breakdowns.
- Add tests for stale auth, expired account sessions, missing binaries, quota exhaustion, and malformed CLI output.

Acceptance:

- The dashboard and router show only configured providers by default.
- Provider recommendations explain live availability, capability fit, limit pressure, accuracy, speed, cost, and recent reliability.

### Sprint E - Cross-Machine Conflict Center

Goal: make CloudKit sync and multi-machine coordination inspectable and reversible.

- Add an operation-envelope inspector for changes produced by autonomous tasks, provider runs, settings edits, snapshots, and AgentNotes reconciliation.
- Show local/remote record versions, source machine, timestamps, affected entity counts, and proposed resolution.
- Add conflict dry-run previews with "keep local", "accept remote", "merge", "restore snapshot", and "restore into new local copy" options.
- Add audit trail links from conflicts to source run/task/plan.
- Add multi-store tests that simulate divergent records and stale machine peers.

Acceptance:

- Users can understand and resolve conflicts without guessing which machine changed what.
- Every destructive conflict action has a preview and rollback path.

### Sprint F - Trusted Autopilot Lanes

Goal: make autonomy feel inevitable, safe, and beautiful without skipping safety boundaries.

- Define scoped trust lanes for read-only review, plan-only, test-only, small-file edits, docs-only edits, dependency updates, and commit/push.
- Add per-workspace policy templates with explicit allowed roots, protected paths, command allowlists, network policy, budget caps, and validation gates.
- Require a successful snapshot or git checkpoint before higher-risk mutation lanes.
- Add an autonomous loop that executes one bounded task at a time, records evidence, runs validation, and stops on uncertainty.
- Add a reviewable "why this is safe" panel before each escalation.

Acceptance:

- The user can say a goal, see a bounded plan, approve a trust lane, and watch the app progress through reversible, audited steps.
- The app stops safely when policy, validation, sync, provider, or budget state becomes uncertain.

### Sprint G - UI Flow And Visual Regression Coverage

Goal: keep the Liquid Glass experience aligned, calm, and robust across window sizes.

- Add UI tests for prompt router resized layout, command sheet close paths, live run dock, provider setup, settings panes, project edit/delete, project task nesting, AgentNotes stale cleanup, restore preview, and autonomy readiness.
- Capture reference screenshots for dark/light, minimum supported size, medium window, maximized window, and full screen.
- Add screenshot diff thresholds or manual review artifacts under USB-derived validation folders.
- Ensure every button label fits at minimum window width and that action buttons align consistently.

Acceptance:

- Regression tests catch the UI failures reported in the screenshot-driven repair turns.
- Settings and project/workspace controls remain editable and aligned at non-maximized sizes.

### Sprint H - Packaging, Entitlements, And Release Readiness

Goal: turn the developer tool into a durable macOS app distribution.

- Finalize entitlements for CloudKit, CloudDocuments, user-selected read/write files, background remote notifications, and developer-tool category.
- Verify signing against the intended Developer ID/App Store path.
- Add notarization or TestFlight/App Store packaging notes as appropriate.
- Create privacy documentation for local shell execution, provider auth, Keychain storage, CloudKit sync, prompt/output excerpt storage, and logs.
- Add migration tests for additive SwiftData/CloudKit schema changes.
- Add release checklist and rollback plan.

Acceptance:

- Build, archive, sign, and install flows are documented and validated.
- Users understand what syncs to iCloud, what remains local, and what actions require approval.

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

After this Sprint C checkpoint is validated and pushed, the next best implementation unit is Sprint D: provider probe and routing telemetry hardening. That is the narrowest high-value step toward making provider recommendations reflect live auth, quota, reliability, and recent failure state instead of mostly static configuration plus historical outcomes.
