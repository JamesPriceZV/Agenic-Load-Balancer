# AgentPlan.md - Agenic Load-Balancer Comprehensive Implementation Plan

Updated: May 26, 2026

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
- Sprint J from the live-maturity queue is implemented as provider probe maintenance plus XcodeBuildMCP source support. The provider catalog now includes XcodeBuildMCP as a local tool source, auth recipes treat it as no-auth/MCP-configured, safe probe reporting covers installed CLI/provider state without launching login flows, and probe classifiers separate API-key, account-login, custom-profile, quota, rate, subscription, and context signals.
- Sprint K from the live-maturity queue is implemented as the first conflict-recovery drill. The Conflict Center can seed a local synthetic two-machine recovery scenario, merge commutative audit history, plan restore-into-new-copy for risky task divergence, persist the drill evidence into SwiftData, and refresh CloudKit save status without mutating target entities.
- Sprint L from the live-maturity queue is implemented as the first screenshot-diff visual-regression matrix. UI tests now capture dashboard, Prompt Router, Settings Tools, Projects, and Conflict Center screenshots, attach JSON visual fingerprints, assert structural visual metrics, and run through `script/visual_regression.sh` with USB-backed results.
- Sprint M from the live-maturity queue is implemented as repo-owned doctor automation for the remaining release-maturity seams: provider drift, Foundation Models host health, physical CloudKit drill manifests, bounded-autonomy continuation safety, and Developer ID/notary credential readiness.
- Sprint N from the live-maturity queue is implemented as physical release-validation tooling: two-Mac CloudKit coordination with Solaris971 defaults and manual fallback, expanded screenshot-diff matrices, Xcode-managed Developer ID export support, and refreshed provider/Foundation/autonomy/release evidence.
- Sprint Q.3 from the live-maturity queue is implemented as the autonomous loop scheduler. `Services/AutonomousLoopScheduler.swift` walks an already-persisted `PersistedAutonomousPlan` in topological dependency order, evaluates each task against the active `AutonomyPolicy`, marks advisory tasks complete without launching a provider, runs the existing `ValidationGateRunning` for tasks with a validation command, and halts immediately on policy denial, approval-required, validation failure, iteration/validation/approval cap, or dependency deadlock. Audit-trail rows are written at every iteration boundary so the History view can rebuild what happened. `AutonomousLoopSchedulerTests` covers the happy path, validation failure halt, missing-validation-command approval surface, lane-restriction denial, iteration cap, and the topological-order helper (with cycle fallback).
- Sprint Q.4 from the live-maturity queue is implemented as the actual restore-into-new-copy workflow. `Services/RestoreIntoNewCopyWorkflow.swift` introduces a pure `RestoreIntoNewCopyPlanner` that consumes a `ConflictResolutionPreview` plus pre-fetched SwiftData rows (project, autonomy tasks, operations, audits) and emits a scoped clone plan with size estimation against an exclude list for `.git`, `node_modules`, `DerivedData`, and other known caches. `RestoreIntoNewCopyApplier` inserts a cloned `AgentProject`, cloned `AutonomyTaskRecord` rows, cloned `AutonomyOperationRecord` envelopes, cloned `AuditTrailRecord` entries (all with `restore::<conflictID>::...` lineage identifiers), creates a sibling directory `<root>__divergence-<shortConflictID>` under the source root's parent, writes `DIVERGENCE.md`, an isolated `AgentNotes.md` divergence note, and a `cloned-rows.json` row dump, and recursively copies workspace files (skipping the excluded caches). When the estimated workspace size meets or exceeds the configurable large-size threshold (default 100 MB), the applier refuses to copy files without an explicit `allowLargeCopy=true` opt-in, but the SwiftData row clone always proceeds. `WorkspaceCopyManager` lists, archives (`<root>__archived`), and deletes divergence workspaces, including the SwiftData clone rows scoped by lineage prefix. `ConflictCenterView` now wires `.restoreIntoNewCopy` to the workflow, surfaces a confirmation dialog when the planner flags a large-size copy, and exposes a Workspace Copies management section listing divergence workspaces with per-row archive/delete actions. Source rows, the original AgentNotes file, and any files inside the original project root remain untouched.
- Sprint Q.1 from the live-maturity queue is implemented as entity-specific merge policies. `Services/EntityMergePolicy.swift` adds per-entity field-level rules (preferNonEmpty, preferLatest, concatLines, immutableHardConflict, stateMachineFavorTerminal, userRatedWinsOverInferred) for `AgentProviderProfile`, `AutonomyTaskRecord`, and `RunOutcomeRecord`. `ConflictResolutionEngine.resolve` consults the policy before the generic Lamport fallback, returning a deterministic merged payload for safe fields and a precise hard-conflict marker (with field names) for risky ones. Unknown entity types still use the pre-Sprint-Q.1 Lamport rule.
- Sprint Q.2 from the live-maturity queue is implemented as provider remediation and visual-regression polish. Provider setup rows now expose `Re-probe` remediation for stale, missing, or warning freshness states; actionable provider rows sort ahead of healthy rows in deterministic UI fixtures; History shows continuation-chain evidence for failed/continued runs; Conflict Center recovery drill status/actions have stable UI identifiers; and Settings > Agents has a deterministic Foundation Models diagnostics fixture for screenshot coverage. `script/visual_regression.sh` now includes the Sprint Q.2 remediation matrix.
- Sprint P from the live-maturity queue is implemented in two follow-on slices on top of Sprint O.1:
  - **P.1 — continuation telemetry rollup.** `ProviderReliabilitySnapshot` gained additive continuation-chain telemetry (`continuationOfferedRunCount`, `continuationAutoResumeRunCount`, `continuationApprovalGatedRunCount`, `continuationRefusedRunCount`, `maxContinuationChainDepth`). `ProviderReliabilityBuilder.build` consumes `RunOutcomeRecord.continuation*` fields, applies a refusal penalty atop the existing reliability math, and folds the auto/approval/refused split into the summary text. `DashboardMetricFactory.heatmapCells` now exposes a "Continuation" cell rendered by the same green/teal/red gradient as the other reliability metrics.
  - **P.2 — provider setup status badges.** `Services/ProviderSetupBadge.swift` derives four deterministic badges per provider (binary / auth / credentials / freshness) plus a rolled-up `overallTone`. The Providers catalog renders a tone-colored `ProviderSetupBadgeStrip` with hover help and accessibility identifiers `ProviderRow.<id>.Badge.<kind>`.
- Sprint O from the live-maturity queue is implemented in four slices:
  - **O.1 — provider continuation loops.** `ProviderContinuationPolicy` encodes per-provider eligibility, chain-depth caps, approval-gating, and resume notes. `WorkspaceSourceSummarizer` produces deterministic head/tail excerpts of recently modified source files. `TokenBudgetEstimator.prepareContinuation` returns an explicit `ContinuationDecision` (`.prepared` or `.notEligible`) consulted by `RunDispatcher.finalize`. `RunOutcomeRecord` gained additive continuation chain metadata (trigger category, chain depth, parent run ID, approval flag, workspace excerpt count, policy note) round-tripped through `RunOutcomeDTO`. The Outcome sheet's continuation panel surfaces depth/trigger/approval state.
  - **O.2 — visual regression expansion.** App launch handles `--ui-appearance light|dark`, `--ui-maximize`, and `--ui-provider-edge-cases`. The UI fixture bootstrap optionally seeds a missing-binary provider, a needs-token provider, and a failed run outcome with continuation chain metadata. New UI tests `testSprintOMaximizedWindowSnapshotMatrix`, `testSprintODarkAppearanceSnapshotMatrix`, `testSprintOLightAppearanceSnapshotMatrix`, `testSprintOProviderSetupEdgeCaseSnapshotMatrix`, and `testSprintORunSheetSuccessFailureSnapshotMatrix` are wired into `script/visual_regression.sh`.
  - **O.3 — notarization unblock prep.** `script/release_candidate.sh` adds `--notarize-only`, `--staple-only`, `--assess`, `--use-existing-package`, and `--notary-runbook`, plus a documented resume path under `ReleaseReadiness.md`. The runbook prints the App Store Connect API-key and Apple ID + app-specific-password lanes without ever asking for the secret on the command line.
  - **O.4 — Solaris971 drill prep.** `script/two_mac_cloudkit_drill.sh` adds `--peer-bundle`, `--verify-peer-evidence`, `--resume`, and `--remote-login-runbook`. The peer bundle is a self-contained directory with a `run-peer.sh` wrapper, drill-id pin, and README so the secondary manifest can be produced without SSH. Returned manifests are sha256-verified before they count toward the completion gate.
- Sprint Q.4 validation status: implementation-complete; tests need to be run on a macOS host because this branch was prepared from the Linux-based remote execution environment. Recommended focused test invocation: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet test -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS,arch=arm64" -only-testing:"Agenic Load-BalancerTests/RestoreIntoNewCopyWorkflowTests" -only-testing:"Agenic Load-BalancerTests/ConflictResolutionEngineTests" -only-testing:"Agenic Load-BalancerTests/AutonomousLoopSchedulerTests"`. The Conflict Center button strip changed semantics for `.restoreIntoNewCopy` (no longer disabled when no snapshot anchor exists, because the new workflow does not require one); the existing screenshot-diff matrices remain valid and a Sprint Q.4 visual matrix for the Workspace Copies management section is the next visual-regression follow-on.
- Sprint O/P/Q validation closeout is complete through Q.3. Focused Sprint O/P/Q tests passed at `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintOPQ_Tests_20260525_231201/Results/SprintOPQ.xcresult`. Sprint Q.2 focused unit/readiness/conflict tests passed at `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintQ2_Tests_20260526_FINAL/Results/SprintQ2.xcresult`. Sprint Q.3 focused scheduler/autonomy/conflict tests passed at `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintQ3_Tests_20260526_133737/Results/SprintQ3.xcresult`. Expanded screenshot-diff visual regression passed all selected Sprint L/N/O matrices, including maximized, dark, light, provider setup edge cases, and run-sheet success/failure states, at `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintOPQ_Visual_20260525_231504/Results/VisualRegression.xcresult`; the refreshed full visual matrix including the new Sprint Q.2 remediation coverage passed at `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintQ2_Visual_20260526_010200/Results/VisualRegression.xcresult`. Live maturity refresh passed provider probe maintenance, Foundation Models live check, Developer ID/notary credential doctor, CloudKit conflict manifest, and bounded-autonomy continuation drill with report `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintOPQ_LiveMaturity_20260525_232024/live-maturity-report.md`.
- Future work remains, but it should be treated as scoped live-maturity operations after Sprint O rather than unfinished Phase 7.3-7.6 implementation.

## What Is 100 Percent Implemented In The Active Tree

- macOS SwiftUI app shell with Liquid Glass-inspired navigation, dashboard, prompt router, providers, projects, restore, AgentNotes, autonomy, history, and in-app settings surfaces.
- SwiftData schema for projects, provider profiles, command profiles, usage snapshots, routing decisions, run outcomes, coordination events, snapshots, autonomy goals/plans/tasks, policies, machine peers, validation gates, conflict records, and audit trail entries.
- CloudKit/private iCloud configuration for SwiftData sync and app-level sync status display.
- Keychain reference model for secrets, with SwiftData/CloudKit storing references and setup metadata only.
- Provider catalog and setup wizard with install instructions, account/browser login lanes, API-key lanes, verification commands, auth probes, docs links, custom command profiles, environment hints, and XcodeBuildMCP as a local tool-source entry for build/test/debug/log/screenshot/UI-automation workflows when the MCP connector is configured.
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
- Screenshot-diff visual regression smoke matrix for dashboard, Prompt Router, Settings Tools, Projects, and Conflict Center, with screenshot and JSON metric attachments retained in the `xcresult` bundle.
- Live-maturity doctor scripts that safely rehearse or report provider-probe drift, Foundation Models live availability, Developer ID/notary credential readiness, CloudKit physical drill prerequisites, and bounded-autonomy continuation safety seams without running installers or login flows.
- Expanded Sprint N visual regression matrix for command bar overlay, providers catalog, project settings policy, workspace task tree, workspace task detail, Restore, Autonomy, History, and AgentNotes reconciliation.
- Expanded Sprint O visual regression matrix for light appearance, dark appearance, maximized window geometry, provider setup edge cases, and run-sheet success/failure surfaces.
- Sprint Q.2 remediation visual matrix for provider `Re-probe` actions, Conflict Center recovery drill status, History continuation-chain depth, and deterministic Foundation Models diagnostics fixture states.
- Provider setup remediation actions for stale/non-fresh provider health checks, with deterministic provider row ordering so actionable setup issues remain visible in compact windows and visual fixtures.
- History continuation panels that surface trigger, depth, parent run, approval-gating, workspace-excerpt count, and policy-note evidence for continuation-capable outcomes.
- Deterministic Settings > Agents Foundation Models diagnostics fixture for visual regression and host-state UI coverage without requiring live Apple Intelligence availability during UI tests.
- Xcode-managed Developer ID archive/export path for this project, including `ALLOW_XCODE_MANAGED_SIGNING=1` and `ALLOW_PROVISIONING_UPDATES=1` release-script support. The latest export is signed by `Developer ID Application: Zinco Verde, Inc. (A45694H5ZG)` with hardened runtime and production CloudKit entitlements.

## What Is Partial Or Needs Live-System Validation

- Live Foundation Models happy path now has an explicit in-app diagnostics route and a scriptable `script/foundation_models_check.sh` live check. The May 25, 2026 host returned a minimal `LanguageModelSession` response successfully on macOS 26.5, but this remains periodic live validation because Apple Intelligence availability, locale, policy, and model behavior can drift by machine.
- CloudKit sync is wired, status is observable, Sprint E exposes a conflict inspection/resolution surface, Sprint K adds a local recovery drill, Sprint M adds role-specific physical drill manifests, and Sprint N adds `script/two_mac_cloudkit_drill.sh`. The May 25, 2026 run generated local evidence and a peer command for Solaris971, but Solaris971 refused SSH on port 22, so physical two-Mac completion still needs peer-side manifest/screenshots and repeated multi-device, multi-account, network-failure, and CloudKit conflict-injection validation.
- Provider auth recipes are grounded in official flows and expose account/API-key lanes. Sprint J adds a safe live probe report, XcodeBuildMCP source support, and Sprint M adds baseline-aware `script/provider_probe_maintenance.sh`, but each provider's login, subscription state, quota endpoint, and CLI behavior can still change and needs recurring probe maintenance.
- Context compaction now covers pre-dispatch AgentNotes pressure and run telemetry, and context-window failures now create continuation prompts. A full autonomous continuation loop still needs provider-specific resume execution policies and richer source-file summarization before the app can safely continue long work without approval.
- Autonomy now has trusted-lane policy templates, per-task safety reviews, and `script/autonomy_continuation_drill.sh` to confirm the bounded continuation seams stay wired. It remains deliberately bounded: arbitrary repo mutation, multi-step unattended execution, and recovery still require future live validation and explicit approval boundaries.
- UI validation now has launch coverage, minimum-window flow coverage, deterministic workspace/task coverage, the Sprint L smoke matrix, the Sprint N expanded app-surface matrix, the Sprint O light/dark/maximized/provider-edge/run-sheet matrix, and the Sprint Q.2 remediation matrix for Conflict Center recovery, History continuation depth, provider re-probe actions, and Foundation Models diagnostics fixture states. Remaining visual coverage should focus on true full-screen permutations, the new Sprint Q.4 Workspace Copies management section, baseline-history comparison, and deeper live diagnostics variants.
- Conflict resolution now has deterministic primitives, audit records, a user-facing dry-run Conflict Center, a local recovery drill that proves safe audit merge and risky divergence restore planning, and the Sprint Q.4 restore-into-new-copy workflow with planner, applier, sibling-directory clone, size-aware confirmation, and a Workspace Copies manager. The remaining "perfect conflict resolution" promise needs physical cross-machine recovery drills against real project data.
- Release signing now produces a Developer ID signed app/ZIP through Xcode-managed signing, but notarization is still blocked in this shell because no `notarytool` keychain profile is visible. Gatekeeper currently reports `source=Unnotarized Developer ID`; create/select `NOTARY_PROFILE` or `ALB_NOTARY_PROFILE`, then rerun notarize/staple.

## Deferred Future Queue

- Live Foundation Models smoke suite: run command bar, run summary, AgentNotes intelligence, and tie-breaker against real on-device Foundation Models and record observed availability states.
- Sprint P.1 follow-on: add live-CLI smoke runs that intentionally exhaust a provider's context window to confirm the auto-resume path on Codex/Claude Code matches the new policy, and bring the continuation-chain rollup into the trendline + dashboard exports.
- Provider-specific live probe maintenance: keep the Sprint J safe report current as CLIs change, then expand normalized probe coverage with per-provider quota endpoints, subscription freshness checks, version drift detection, and recurring live auth/login validation.
- Cross-machine sync validation: run Solaris551 and Solaris971 against the same CloudKit container. Use `script/two_mac_cloudkit_drill.sh --remote-login-runbook` to enable Remote Login, or `--peer-bundle` to produce a USB-stick bundle for offline use. Bring the secondary manifest/screenshots back, hash-verify with `--verify-peer-evidence`, and document conflict outcomes beyond the Sprint K local drill.
- Conflict resolution expansion: Sprint Q.1 landed entity-specific merge policies for ProviderProfile, AutonomyTask, and RunOutcome. Sprint Q.4 landed the actual restore-into-new-copy workflow (planner + applier + Workspace Copies manager) with size-aware confirmation and archive/delete management. Remaining work is multi-device recovery drills against intentionally divergent CloudKit records.
- Trusted-autopilot expansion: build on the new Sprint F lane templates with richer live evidence collection, automatic snapshot creation, bounded multi-step execution, and per-lane recovery drills.
- Autonomous loop scheduler: Sprint Q.3 landed the bounded `AutonomousLoopScheduler` that walks an existing plan, runs the validation gate where present, halts on approval-required/denied/cap conditions, and writes audit-trail rows for every iteration. Sprint Q.5 landed the persisted `AutonomousLoopReportRecord` (CloudKit-compatible, additive schema), automatic report persistence at the end of every scheduler run, the Autonomy control room Loop History panel with halt-reason chips and a compact iteration timeline, and decode helpers that round-trip iterations from stored JSON. Sprint Q.6 landed the drill-down Loop Report Detail sheet with a per-iteration card list, filter toggle (all / failures / approvals / validation), task roll-up, and a "Copy JSON" button. Sprint Q.7 landed validation transcript excerpts on each iteration so the drill-down can surface why a gate failed without re-running the command. Sprint Q.8 landed user-configurable loop budget caps (with clamped safety bounds) and a "Run Loop" button in the Autonomy control room that invokes the scheduler against the persisted plan with the resolved budget. Sprint Q.9 landed a Markdown renderer + "Copy Markdown" button so reports can be pasted directly into GitHub issues, PRs, or `AgentNotes.md`. Sprint Q.10 landed a retention policy with safe-bounded per-plan and age caps; retention runs after every Run Loop walk and the most recent report per plan is always preserved. Remaining future work is live-running the scheduler end-to-end against a real workspace.
- Provider setup UX: Sprint P.2 landed the four-badge strip (binary / auth / credentials / freshness) plus the tone roll-up, and Sprint Q.2 landed the first safe `Re-probe` remediation action for non-fresh provider health. Remaining future work is per-provider docs snapshots, approval-gated install/login remediation commands, and trendline freshness gating.
- Visual regression coverage expansion: Sprint Q.2 landed Conflict Center recovery, continuation depth, provider remediation, and Foundation Models diagnostics fixture coverage. Remaining future work is true full-screen coverage, Sprint Q.4 Workspace Copies management screen coverage, live diagnostics variants, and baseline-history comparison/export.
- Packaging and release: create or select a `notarytool` keychain profile (see `script/release_candidate.sh --notary-runbook`), rerun `script/release_candidate.sh --notarize-only --staple` against the signed ZIP under the most recent USB run root, verify Gatekeeper acceptance, then finalize onboarding, privacy copy, crash/log policy, and upgrade/migration tests.

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

### Sprint I - Release Candidate Credential Drill

Goal: make signed Developer ID archive/notarization executable from the repo while keeping secrets out of SwiftData, CloudKit, and planning docs.

- Added `script/release_candidate.sh` for credential-aware Developer ID release drills.
- The script checks for a real `Developer ID Application` signing identity via `security find-identity`, requires `NOTARY_PROFILE`/`ALB_NOTARY_PROFILE` for notarization, writes export options into the USB-backed `RUN_ROOT`, and runs archive, export, ZIP package, notary submit, staple, and Gatekeeper assessment steps on demand.
- The script supports `--verify-credentials`, `--archive`, `--export`, `--package`, `--notarize`, `--staple`, `--all`, and `--dry-run`.
- `ReleaseReadiness.md` now documents the credential drill, notary profile setup, and the no-secret policy for Apple account material.
- `ReleaseReadinessTests` now guards the release-candidate script contract.

Validation:

- `bash -n script/release_candidate.sh script/release_preflight.sh` passed.
- `script/release_candidate.sh --help` printed the expected option/credential contract.
- `script/release_candidate.sh --verify-credentials` correctly blocked on this Mac because only Apple Development identities are installed; no `Developer ID Application` identity was present.
- Focused `ReleaseReadinessTests` passed with result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintI_Release_20260522_145907/Results/ReleaseReadiness.xcresult`.

### Sprint J - Provider Probe Maintenance And XcodeBuildMCP Source

Goal: make live provider/source status observable without leaking secrets or launching login/install flows.

- Added XcodeBuildMCP to `ProviderCatalog` as a `tool-source` provider with `xcodebuild -version` verification, no provider login requirement, and docs pointing to the XcodeBuildMCP configuration guide.
- Added an XcodeBuildMCP `ProviderAuthRecipe` that records `session_show_defaults` and `xcodebuild -version` as safe probes and documents that macOS/device/debug/UI automation workflows depend on the user's MCP configuration.
- Added safe XcodeBuildMCP command defaults in `GenericCLIAdapter`: use `xcodebuild -list -project <first project>` when a workspace contains an Xcode project, otherwise use `xcodebuild -version`.
- Hardened provider probe classification so API-key evidence is not collapsed into generic account sign-in, and live text can infer auth and limit state from health messages/detail lines before falling back to catalog state.
- Added `script/provider_probe_report.sh`, a safe report generator that checks local provider binaries, non-secret environment-variable presence, version/auth diagnostics, Apple Foundation Models diagnostic posture, XcodeBuildMCP local toolchain availability, and custom-profile needs without running installers, browser auth, device-code auth, or commands that intentionally print secrets.
- Added regression tests for XcodeBuildMCP catalog/auth/default-command support, safe probe-report script contract, provider-output auth/limit classification, and live-output-first report summarization.

Validation:

- `bash -n script/provider_probe_report.sh script/release_candidate.sh script/release_preflight.sh` passed.
- XcodeBuildMCP `session_show_defaults` is callable in this Codex session and currently reports no active project/workspace/scheme/simulator defaults configured, which is why app support treats XcodeBuildMCP as a configurable source rather than assuming a ready build target.
- Safe provider probe report completed with `RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_ProviderProbe_20260522_161704" PROBE_TIMEOUT_SECONDS=4 script/provider_probe_report.sh`; output recorded Codex, Claude, GitHub CLI, Gemini, and XcodeBuildMCP/xcodebuild availability while redacting token text.
- Focused ProviderWizard/catalog tests passed with result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintJ_Provider_20260522_161138/Results/ProviderProbe.xcresult`.

### Sprint K - Multi-Machine Conflict Recovery Drill

Goal: make cross-machine recovery behavior rehearsable inside the app before live two-machine CloudKit drills.

- Added `ConflictRecoveryDrill`, a deterministic local drill that creates synthetic local/remote machine peers, a rollback snapshot anchor, a safe commutative `appendAudit` conflict, and a risky concurrent `setStatus` task divergence.
- Added a Conflict Center `Run Drill` action that seeds the scenario into SwiftData, runs the same preview/resolution machinery users inspect manually, records local save activity, and reports whether the recovery rehearsal passed.
- The drill applies `.merge` to safe audit-history conflict records and `.restoreIntoNewCopy` to risky operation-log divergence, creating a backing synthetic conflict record when needed.
- The drill persists peer, operation, conflict, and snapshot evidence but does not mutate target project/task entities, so it is safe to run as a rehearsal and as regression coverage.
- Added focused tests proving the drill records a merge, plans restore into new copy, preserves stale-peer warnings, anchors the snapshot, and persists the synthetic records in an in-memory SwiftData container.

Validation:

- Focused conflict drill tests passed with `RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintK_Conflict_20260522_164834" DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test ... -only-testing:"Agenic Load-BalancerTests/ConflictResolutionEngineTests"`; result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintK_Conflict_20260522_164834/Results/ConflictDrill.xcresult`.

### Sprint L - Screenshot-Diff Visual Regression

Goal: catch blank, flattened, clipped, or badly shifted Liquid Glass UI regressions before screenshots reach the user.

- Added `testSprintLVisualRegressionSnapshotMatrix()` to the macOS UI-test target.
- Captures dashboard, Prompt Router, Settings Tools, Projects, and Conflict Center screenshots under deterministic `--uitesting` fixtures.
- Computes visual fingerprints from each screenshot: pixel dimensions, sampled pixel count, coarse color bucket count, mean luminance, luminance standard deviation, and average neighbor delta.
- Asserts each target view remains nonblank, sufficiently detailed, structurally contrasted, and within expected luminance bounds.
- Keeps screenshot attachments and JSON metric attachments in the `xcresult` bundle with `.keepAlways`.
- Treats standalone PNG/JSON file export as best effort because macOS UI-test sandboxes can deny arbitrary output writes; the `xcresult` attachments are the authoritative visual evidence.
- Added `script/visual_regression.sh` to run the matrix with USB-backed `DerivedData`, build products, and result bundles.

Validation:

- `RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintL_Visual_20260525_104900" script/visual_regression.sh` returned `** TEST SUCCEEDED **`.
- Result bundle: `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintL_Visual_20260525_104900/Results/VisualRegression.xcresult`.
- The passing run executed one UI test in 40.961 seconds and retained screenshots plus metric JSON attachments for all five Sprint L surfaces.

### Sprint M - Live Maturity Doctors

Goal: make the remaining live-release seams repeatable, observable, and honest without pretending that physical devices or Apple signing credentials can be simulated.

- Added `script/live_maturity_check.sh` as the orchestration entry point for recurring release-maturity checks.
- Added `script/provider_probe_maintenance.sh` to run the safe provider probe report, optionally compare it against a baseline report, and classify provider drift as captured, stable, changed, or blocked.
- Added `script/foundation_models_check.sh` to compile and run a minimal Swift Foundation Models availability/response probe under a USB-backed run root. It reports framework availability, model availability, response text, duration, and strict/pass/fail status without making Foundation Models a requirement for normal app behavior.
- Added `script/cloudkit_conflict_drill.sh` to generate local, primary, or secondary physical-drill manifests for a real two-machine CloudKit conflict test. The local manifest is a rehearsal; primary/secondary roles remain blocked until peer evidence is supplied.
- Added `script/autonomy_continuation_drill.sh` to verify the bounded autonomy continuation seams remain present: trust lanes, approval requirements, task preparation, validation gates, rollback evidence, and changed-file caps.
- Added release-readiness regression coverage so the Sprint M doctor scripts stay wired into the repo contract.
- Kept Developer ID archive/notarization blocked unless `script/release_candidate.sh --verify-credentials` finds a real Developer ID Application identity and notarytool profile; the new doctor reports that blocker instead of hiding it.
- Kept every live-maturity script non-secret and non-invasive: no installers, browser login, device-code auth, or provider-login commands run silently.

Acceptance:

- A maintainer can run one command to learn which live-release maturity items are green, blocked, or awaiting physical evidence.
- Foundation Models, provider probes, Developer ID credentials, CloudKit physical drills, and autonomy continuation checks all produce repo-owned reports under a chosen `RUN_ROOT`.
- The app remains honest that physical multi-machine CloudKit validation, live provider auth/quota drift, and Developer ID/notary credentials are live-system dependencies.

Validation:

- `bash -n script/foundation_models_check.sh script/provider_probe_maintenance.sh script/cloudkit_conflict_drill.sh script/autonomy_continuation_drill.sh script/live_maturity_check.sh script/visual_regression.sh script/provider_probe_report.sh script/release_candidate.sh script/release_preflight.sh` passed.
- `RUN_ROOT="/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintM_LiveMaturity_20260525_110600" PROBE_TIMEOUT_SECONDS=4 script/live_maturity_check.sh` completed with provider probe maintenance, Foundation Models live check, CloudKit manifest, and bounded-autonomy drill succeeding while Developer ID/notary remained correctly blocked by missing release credentials.
- Live maturity report: `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintM_LiveMaturity_20260525_110600/live-maturity-report.md`.
- Focused `ReleaseReadinessTests` passed with result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintM_Tests_20260525_111000/Results/ReleaseReadiness.xcresult`.

### Sprint N - Physical Live Release Validation

Goal: convert the remaining live-release queue into concrete release evidence while preserving honest gates for physical peer proof and Apple notarization.

- Added `script/two_mac_cloudkit_drill.sh`, a physical two-Mac CloudKit coordination wrapper that defaults to `Solaris971.local`, attempts SSH when Remote Login is available, emits an exact peer command when SSH is unavailable, captures local primary evidence, and refuses to mark the physical drill complete without peer manifest/screenshots.
- Wired `script/live_maturity_check.sh --two-mac-cloudkit` and included it in `--all` so the live-maturity report can show physical CloudKit coordination status alongside provider, Foundation Models, release, conflict, and autonomy checks.
- Expanded `script/visual_regression.sh` to run both Sprint L and Sprint N UI snapshot matrices. Sprint N covers command bar overlay, providers catalog, project settings policy, workspace task tree, workspace task detail, Restore, Autonomy, History, and AgentNotes reconciliation.
- Updated `script/release_candidate.sh` so Xcode-managed Developer ID signing can be attempted with `ALLOW_XCODE_MANAGED_SIGNING=1` and `ALLOW_PROVISIONING_UPDATES=1` when the Developer ID private key is managed by Xcode rather than visible through `security find-identity`.
- Extended `ReleaseReadinessTests` to guard the two-Mac drill wrapper, managed-signing release path, and expanded visual matrix.

Acceptance:

- A maintainer can run one live-maturity command that attempts the physical peer path and leaves a truthful manual peer command if Solaris971 is reachable on the network but Remote Login is unavailable.
- The signed release lane can export a hardened-runtime Developer ID app/ZIP with production CloudKit entitlements through Xcode-managed signing.
- The app has screenshot-diff coverage over the broader navigation and workflow surfaces that were previously only manually inspected.

Validation:

- `bash -n script/foundation_models_check.sh script/provider_probe_maintenance.sh script/cloudkit_conflict_drill.sh script/two_mac_cloudkit_drill.sh script/autonomy_continuation_drill.sh script/live_maturity_check.sh script/visual_regression.sh script/provider_probe_report.sh script/release_candidate.sh script/release_preflight.sh` passed.
- Focused `ReleaseReadinessTests` passed with result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_SprintN_Tests_20260525_123532/Results/ReleaseReadiness.xcresult`.
- Expanded visual regression passed with result bundle `/Volumes/USB256/Xcode_Projects_Storage/Agenic_VisualExpanded_20260525_123822/Results/VisualRegression.xcresult`; `testSprintLVisualRegressionSnapshotMatrix` and `testSprintNExpandedVisualRegressionSnapshotMatrix` both passed.
- Live maturity `--all` passed with report `/Volumes/USB256/Xcode_Projects_Storage/Agenic_LiveMaturity_20260525_124427/live-maturity-report.md`; Foundation Models returned `framework=available`, `availability=available`, and `response=OK`; provider probe maintenance captured a current report; autonomy continuation remained `bounded`.
- Two-Mac CloudKit coordination generated drill ID `cloudkit-drill-20260525T164444Z` on local machine `Solaris551`; peer `Solaris971.local` refused SSH on port 22, so the generated peer command is the next physical evidence step.
- Managed Developer ID export produced `/Volumes/USB256/Xcode_Projects_Storage/Agenic_ReleaseManaged_20260525_121347/Export/Agenic Load-Balancer.app` and `/Volumes/USB256/Xcode_Projects_Storage/Agenic_ReleaseManaged_20260525_121347/Packages/Agenic Load-Balancer.zip`. `codesign` reports `Developer ID Application: Zinco Verde, Inc. (A45694H5ZG)`, hardened runtime, and production CloudKit entitlements. `spctl` currently rejects only as `source=Unnotarized Developer ID`; no `com.apple.gke.notary.tool` keychain profile is visible yet.

### Sprint Q.10 - Loop Report Retention Policy

Goal: stop the persisted scheduler-report store from growing unbounded, while keeping the most recent report per plan visible so the Loop History panel never goes blank.

- Added `Services/AutonomyLoopReportRetention.swift` — a pure `AutonomyLoopReportRetentionPolicy` struct that owns `maxReportsPerPlan` and an optional `maxAgeDays` plus a `clamped(...)` factory keyed off raw @AppStorage values (with `0` meaning "no age limit"). Static `prune(...)` computes the identifiers to drop, always preserving the most-recent report per `planID`, then dropping reports that exceed the per-plan cap, then dropping reports older than `maxAgeDays`.
- Added `AutonomousLoopPersistence.applyRetention(policy:modelContext:now:)` — fetches all `AutonomousLoopReportRecord` rows, calls `prune`, deletes matching rows, and saves. Returns the deleted count so the UI can confirm the cleanup. Failures are non-fatal — retention is best-effort housekeeping.
- Added two @AppStorage keys to `AutonomyControlCenterView` (`Agenic.autonomy.retention.maxReportsPerPlan`, `Agenic.autonomy.retention.maxAgeDays`) with sensible defaults (20 reports / no age limit) and a Loop Retention section in the safety panel (two bounded steppers + summary chip + clarifying caption + stable accessibility identifiers).
- Wired retention into `runAutonomousLoop` so every Run Loop click prunes immediately after the scheduler walk; the status line now reports the prune count when it's non-zero.
- Added `AutonomyLoopReportRetentionTests` covering: default policy keeps a small store intact, per-plan cap prunes oldest, latest-per-plan is always preserved (even over the age limit), age limit drops old reports without losing the latest, retention scopes each plan separately, in-range clamping, zero-age disables, below-min raise, above-max lower, summary text contains caps + age, SwiftData round-trip deletion, and the no-op case.

Acceptance:

- A user with 200 stored loop reports can configure retention via the safety panel, run a loop, and see the Loop History panel collapse to the configured cap with the most recent report per plan preserved.
- Out-of-range storage values clamp to safe maxima; zero-age input maps to "no age limit".
- Retention always preserves the most recent report per plan even if it's older than the configured age limit, so the Loop History panel never goes blank.

Validation:

- Tests are implementation-complete and need to be run on a macOS host. Recommended focused invocation: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet test -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS,arch=arm64" -only-testing:"Agenic Load-BalancerTests/AutonomyLoopReportRetentionTests" -only-testing:"Agenic Load-BalancerTests/AutonomyLoopBudgetConfigTests" -only-testing:"Agenic Load-BalancerTests/AutonomousLoopSchedulerTests"`.

### Sprint Q.9 - Loop Report Markdown Export

Goal: let users paste a persisted scheduler report straight into a GitHub issue, PR, or `AgentNotes.md` without massaging the JSON by hand.

- Added `Services/AutonomyLoopReportMarkdown.swift` — a pure renderer with a single `render(_:)` entry point that decodes the persisted iteration JSON, formats halt-reason / metadata / iteration cards / validation transcript excerpts / task roll-up as Markdown, and returns a string. The renderer never touches global state and never mutates the input record.
- Validation transcript excerpts (Sprint Q.7) render as fenced ` ```text ` blocks so they survive a paste into Markdown contexts.
- `AutonomyLoopReportDetailView` now exposes a "Copy Markdown" button next to "Copy JSON" in the footer with its own confirmation message and accessibility identifier (`Autonomy.LoopReportDetail.CopyMarkdown`).
- Added `AutonomyLoopReportMarkdownTests` covering: header + core fields, full iteration list with validation transcript, empty-iteration / empty-rollup placeholders, and the transcript block omitted when no excerpt is captured.

Acceptance:

- Clicking "Copy Markdown" in the Loop Report Detail sheet places a structured Markdown document on the clipboard that opens cleanly in any Markdown viewer.
- The Markdown renderer survives empty iteration sets, missing transcripts, and empty completed/pending task IDs without producing broken syntax.

Validation:

- Tests are implementation-complete and need to be run on a macOS host. Recommended focused invocation: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet test -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS,arch=arm64" -only-testing:"Agenic Load-BalancerTests/AutonomyLoopReportMarkdownTests" -only-testing:"Agenic Load-BalancerTests/AutonomyLoopReportDetailTests"`.

### Sprint Q.8 - Configurable Autonomy Loop Budget And Run Loop Button

Goal: turn the scheduler into a first-class UI action so the user can run a persisted plan from the Autonomy control room with caps they can tune, and make those caps safe by default.

- Added `Services/AutonomyLoopBudgetConfig.swift` — a `Sendable` `Codable` struct that owns the three scheduler caps plus their min/max bounds and a pure `clamped(...)` static. `asBudget` converts to the runtime `AutonomousLoopBudget`, and `summary` produces the compact "≤N iter · ≤N fail · ≤N approval" label shown in the safety panel.
- Added three `@AppStorage` keys to `AutonomyControlCenterView` (`Agenic.autonomy.maxIterations`, `Agenic.autonomy.maxValidationFailures`, `Agenic.autonomy.maxApprovalsBeforeHalt`) with defaults matching `AutonomousLoopBudget.default`, so existing behaviour is unchanged until the user tunes them.
- Extended the safety panel with a Loop Budget section: a header summary, three steppers bounded by `AutonomyLoopBudgetConfig`'s min/max constants, and an explanatory caption that calls out the clamping contract. Each control carries a stable accessibility identifier (`Autonomy.LoopBudget.Summary`, `.MaxIterations`, `.MaxValidationFailures`, `.MaxApprovalsBeforeHalt`).
- Added a "Run Loop" button to the autonomous work panel that's enabled only when a plan is persisted, a project root is present, no per-task validation is running, and no other loop is already in flight. The button invokes `AutonomousLoopScheduler` with the resolved budget and the existing `ShellValidationGateRunner`. The scheduler's Q.5 auto-persist means the resulting `AutonomousLoopReportRecord` appears immediately in the Loop History panel.
- Added `AutonomyLoopBudgetConfigTests` covering: defaults match the runtime budget, in-range pass-through, below-min raises to the floor, above-max lowers to the ceiling, `asBudget` round-trip, and the summary label contains all three caps.

Acceptance:

- The Autonomy safety panel shows the resolved budget summary and lets the user adjust each cap within safe bounds.
- The Run Loop button walks the persisted plan with the user's budget and surfaces the halt reason in the status line.
- Out-of-range values (whether from corrupted storage or future code) clamp to the safe maxima before the scheduler runs.

Validation:

- Tests are implementation-complete and need to be run on a macOS host. Recommended focused invocation: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet test -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS,arch=arm64" -only-testing:"Agenic Load-BalancerTests/AutonomyLoopBudgetConfigTests" -only-testing:"Agenic Load-BalancerTests/AutonomousLoopSchedulerTests"`.

### Sprint Q.7 - Validation Transcript Excerpt Persistence

Goal: round-trip the validation gate's captured output into the persisted iteration so the Loop Report Detail drill-down can answer "why did this gate fail?" without re-running the command.

- Added `validationOutputExcerpt: String?` to `AutonomousLoopIteration` with a custom initializer that defaults the new parameter to `nil` so existing call sites continue to compile.
- Updated `CodingKeys` to include the new field. Synthesized Decodable conformance treats it as `decodeIfPresent`, so older persisted reports (which lack the key) decode it as `nil`.
- `AutonomousLoopScheduler.run(...)` now passes `result.outputExcerpt` (collapsed to `nil` when empty) into the validation-passed and validation-failed iteration constructors.
- `AutonomyLoopReportDetailView` renders the excerpt under the validation command/exit row when present — monospaced, line-limited, copy-selectable, with a dedicated accessibility identifier per iteration index.
- `AutonomyLoopReportJSON.encode(_:)` adds the excerpt to the per-iteration entry when non-nil so the Copy JSON payload remains complete.
- Added regression coverage: a Codable round-trip with an excerpt, a legacy-JSON decode that asserts a missing key falls back to nil, a JSON-encoder test that surfaces the excerpt in the clipboard payload, and a scheduler integration test that asserts the excerpt is captured end-to-end through `ValidationGateResult.outputExcerpt`.

Acceptance:

- A scheduler walk that fails its validation gate now has an iteration whose `validationOutputExcerpt` contains the captured transcript.
- The Loop Report Detail sheet displays the transcript inline beneath the command and exit code.
- Old JSON payloads decode without error and surface as a `nil` excerpt.

Validation:

- Tests are implementation-complete and need to be run on a macOS host. Recommended focused invocation: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet test -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS,arch=arm64" -only-testing:"Agenic Load-BalancerTests/AutonomyLoopReportDetailTests" -only-testing:"Agenic Load-BalancerTests/AutonomousLoopSchedulerTests"`.

### Sprint Q.6 - Loop Report Detail Drill-Down

Goal: turn the Sprint Q.5 Loop History summary panel into a full drill-down so the user can inspect each iteration, filter by status, and copy the persisted JSON when debugging a scheduler walk.

- Added `AutonomyLoopReportFilter` to `Services/AutonomousLoopScheduler.swift` (`all`, `failuresOnly`, `approvalsOnly`, `validationOnly`) with a pure `apply(to:)` method.
- Added `Views/AutonomyLoopReportDetailView.swift` — a sheet-presented view with halt-reason chip, counter pills, filter segmented control, per-iteration cards (status badge, mode, detail, validation command, exit code, timestamp), task roll-up (completed vs pending), and a "Copy JSON" footer button that uses `NSPasteboard.general` and reports a length confirmation.
- Added `AutonomyLoopReportJSON.encode(_:)` — a stable JSON serializer used by the Copy JSON button and by regression tests so the on-clipboard payload stays predictable.
- Wired the panel into `AutonomyControlCenterView`: each Loop History row is now a `.plain` `Button` whose tap sets a `PresentedLoopReport` wrapper, surfaced through `.sheet(item: $presentedLoopReport)`.
- Added `AutonomyLoopReportDetailTests` covering all four filter modes, JSON round-trip including iteration exit codes / commands, and the empty-report case.

Acceptance:

- A user clicking a row in the Loop History panel sees the full iteration timeline and can switch between four filter modes.
- The Copy JSON button writes a sorted-keys, pretty-printed JSON payload to the system pasteboard that includes the iterations, halt-reason metadata, and completed/pending task IDs.
- The detail view does not mutate any SwiftData state and works against the in-memory container used in tests.

Validation:

- Tests are implementation-complete and need to be run on a macOS host. Recommended focused invocation: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet test -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS,arch=arm64" -only-testing:"Agenic Load-BalancerTests/AutonomyLoopReportDetailTests" -only-testing:"Agenic Load-BalancerTests/AutonomousLoopSchedulerTests"`.

### Sprint Q.5 - Persisted Loop Reports And Loop History Panel

Goal: round-trip the scheduler's `AutonomousLoopRunReport` through SwiftData so the Autonomy control room (and CloudKit sync across machines) keeps a durable record of what the loop did, and so the halt-reason chips and iteration timeline render from persisted state rather than only in-memory state.

- Added `AutonomousLoopReportRecord` to `AgenicDataModel.models` with default-valued fields, no relationships, and JSON-encoded iterations/task IDs so additive schema evolution stays CloudKit-safe.
- Added `Codable` conformance to `AutonomousLoopIteration` (and its `Status` enum was already Codable) so iterations can round-trip through `iterationsJSON`.
- Added `AutonomousLoopHaltReason.kind` so the halt case name persists alongside the user-facing label.
- Added `AutonomousLoopPersistence` (`@MainActor`) with `persistReport`, `decodeIterations`, and `decodeTaskIDs` helpers. The scheduler's `run(...)` path now calls `persistReport` at the end of every walk; failures there are non-fatal so the in-memory report still returns to the caller.
- Added `SnapshotPipeline.deleteAll` clearing of the new model so snapshot replace stays correct.
- Added a `loopHistoryPanel` to `AutonomyControlCenterView` with halt-reason chips (`completed`, `approvalRequired`, `denied`, `validationFailureCap`, `iterationCap`, `approvalCap`, `dependencyDeadlock`), iteration counts, validation/approval counters, and a compact iteration timeline (first 12 iterations + overflow count) rendered as tinted dots so the user can scan the loop at a glance.
- Added `AutonomousLoopSchedulerTests` coverage for: report persistence happy path, validation-failure halt reason persistence, and decode tolerance for malformed JSON.

Acceptance:

- Every scheduler walk lands an `AutonomousLoopReportRecord` row containing the goal/plan IDs, halt reason kind + label, validation/approval counters, completed/pending task IDs, and the iteration JSON.
- The Loop History panel renders the most recent reports with chips and an iteration timeline.
- Persisted reports flow through the existing CloudKit private database without manual mapping.
- Snapshot replace clears the new model alongside the rest of the schema.

Validation:

- Tests are implementation-complete and need to be run on a macOS host. Recommended focused invocation: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet test -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS,arch=arm64" -only-testing:"Agenic Load-BalancerTests/AutonomousLoopSchedulerTests"`.

### Sprint Q.4 - Restore Into New Copy Workflow

Goal: convert the Conflict Center's `.restoreIntoNewCopy` lane from a planning placeholder into the actual scoped clone described in the Sprint K drill plan, with a managed lifecycle for the divergence workspaces that get created.

- Added `Services/RestoreIntoNewCopyWorkflow.swift`.
- `RestoreIntoNewCopyPlanner.plan(...)` is pure: given a `ConflictResolutionPreview` plus pre-fetched SwiftData rows (project, autonomy tasks, operations, audits), it returns a `RestoreIntoNewCopyPlan` with cloned-row plans, a sibling-directory URL when the source has an on-disk project root, an estimated source size (skipping `.git`, `node_modules`, `DerivedData`, `Build`, `.build`, `Pods`, `Carthage`, `.venv`, `target`, `dist`, `out`, `.idea`, `__pycache__`, and other known caches), a large-size threshold, and an `agentNotesDivergenceNote` body.
- `RestoreIntoNewCopyApplier.apply(...)` is `@MainActor` and performs all SwiftData and filesystem mutations:
  - Inserts a new `AgentProject` row (when the source has one) with identifier prefixed `restore::<conflictID>::project::`.
  - Inserts cloned `AutonomyTaskRecord`, `AutonomyOperationRecord`, and `AuditTrailRecord` rows scoped to the conflict's entity. Operation envelopes that referenced the source task get their `entityID` remapped to the cloned task ID.
  - Inserts a high-level `conflict.restoreIntoNewCopy.applied` audit row.
  - Creates `<sourceRoot>__divergence-<shortConflictID>` under the source root's parent. Writes `DIVERGENCE.md`, an isolated `AgentNotes.md` divergence note, and a `cloned-rows.json` row dump. Recursively copies the source workspace, skipping the excluded caches.
  - Refuses to copy the workspace files when the estimated size exceeds the configurable large-size threshold (default 100 MB) unless `allowLargeCopy=true`. The SwiftData row clone always proceeds; the filesystem stage falls back to `.skippedLargeSize` with the metadata files still produced inside the sibling directory.
  - Falls back to `.skippedMissingRoot` or `.notAttempted` when the source has no on-disk project root.
- `WorkspaceCopyManager` lists divergence workspaces (those whose project name carries the `(divergence ` marker, whose `rootPath` carries the `__divergence-` marker, or whose identifier carries the `restore::` lineage prefix), archives the sibling directory to `<root>__archived` while updating the project row's `rootPath`, and deletes the sibling directory plus the cloned SwiftData rows.
- `ConflictCenterView` now wires `.restoreIntoNewCopy` to the planner+applier, surfaces a `confirmationDialog` when the planner flags a large-size copy, exposes a Workspace Copies section that lists divergence workspaces with per-row Archive and Delete buttons, and stops disabling the New Copy button when no snapshot anchor exists (the workflow does not require one).
- Source rows, the original `AgentNotes.md` file, and any files inside the original project root remain untouched.
- Added `RestoreIntoNewCopyWorkflowTests` covering: scoped clone planning, missing-root sibling fallback, applier inserting clones without mutating source rows, sibling-directory + divergence note creation when the root exists, large-size refusal with metadata files still landing, listing/deleting divergence workspaces, archiving the sibling directory, and human-readable byte formatting.

Acceptance:

- Picking `New Copy` in the Conflict Center clones the diverged autonomy task plus its scoped operation/audit history into new SwiftData rows whose identifiers carry a `restore::<conflictID>::...` lineage, leaving the source rows unchanged.
- When the source has an on-disk project root, a sibling directory `<root>__divergence-<shortConflictID>` is created beside it containing `DIVERGENCE.md`, an isolated `AgentNotes.md` divergence note, `cloned-rows.json`, and a recursive copy of the workspace (excluded caches skipped). When the workspace size meets or exceeds the threshold, the user sees an explicit confirmation dialog before files are duplicated.
- A managed Workspace Copies section in the Conflict Center lets the user archive (`<root>__archived`) or delete divergence workspaces without manually editing SwiftData or the filesystem.

Validation:

- Tests are implementation-complete and need to be run on a macOS host because this branch was prepared in the Linux-based remote execution environment. Recommended focused invocation: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet test -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS,arch=arm64" -only-testing:"Agenic Load-BalancerTests/RestoreIntoNewCopyWorkflowTests" -only-testing:"Agenic Load-BalancerTests/ConflictResolutionEngineTests" -only-testing:"Agenic Load-BalancerTests/AutonomousLoopSchedulerTests"`.
- Visual regression matrix coverage for the Workspace Copies section is the next Sprint Q.4 follow-on.

### Remaining Live-Maturity Queue

The remaining queue is now physical two-machine CloudKit conflict recovery execution on Solaris551 and Solaris971 with peer evidence attached, true full-screen visual permutations, baseline-history visual comparison/export, ongoing provider probe upkeep as CLIs drift, periodic live Foundation Models checks on eligible macOS 26.x machines, and notarization/stapling after a `notarytool` keychain profile is selected. Fully autonomous continuation loops remain bounded and approval-gated by design; Sprint M through Sprint Q.10 verify those safety seams instead of removing them. Next pure-code candidates are live end-to-end scheduler runs against a real workspace via the new Run Loop button, Sprint Q.4 visual regression coverage for the Workspace Copies management section, Sprint Q.6/Q.9 visual regression coverage for the Loop Report Detail sheet (now with Copy Markdown), Sprint Q.8/Q.10 visual regression coverage for the Loop Budget + Loop Retention steppers, and live CloudKit divergence drills against the new restore-into-new-copy workflow.
