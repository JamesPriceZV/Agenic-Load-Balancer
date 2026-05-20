# Phase 7.3-7.6 Autonomous Command Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the next Agenic Load-Balancer arc: a natural-language Foundation Models command bar, intelligent AgentNotes preflight and reconciliation, on-device routing tie-breaks, and a safe autonomous multi-agent project development manager with cross-machine sync.

**Architecture:** Keep SwiftData as the canonical app repository, CloudKit as the private sync/backup transport, and `AgentNotes.md` as the project-visible coordination projection. Foundation Models features must be wrapped behind `#if canImport(FoundationModels)`, `@available(macOS 26.0, *)`, `SystemLanguageModel.default.availability`, and testable protocols so the app remains buildable and the UI degrades cleanly when Apple Intelligence is unavailable. Autonomy must run through explicit policy, isolated workspace state, audit records, validation gates, and user approval for high-impact operations.

**Tech Stack:** Swift 6, SwiftUI, Observation, SwiftData, CloudKit private database, FoundationModels (`LanguageModelSession`, `Tool<Arguments, Output>`, `@Generable`, `@Guide`), NSFileCoordinator, Git CLI, Swift Testing, Xcode macOS test target.

---

## Root And Continuity Preflight

- Requested artifact path: `/Users/zincoverde/Library/CloudStorage/OneDrive-Personal/4_XcodeProjects/Agenic Load-Balancer/AgentPlan.md`.
- Live requested root status on May 20, 2026: the folder exists but is not a Git repository. `git rev-parse --show-toplevel` and `git status --short --branch` fail with `fatal: not a git repository`.
- Live requested root contents on May 20, 2026: only `Agenic Load-Balancer.xcodeproj/project.xcworkspace/contents.xcworkspacedata` was present under the requested root. Source files, tests, `AgentNotes.md`, and `PLAN.md` were absent from this root at inspection time.
- Authorized archive source: `/Users/zincoverde/Documents/OneDrive-OLD/4_XcodeProjects/Agenic Load-Balancer`. Per user instruction on May 20, 2026, missing project files and `PLAN.md` may be copied only from this archive source. Do not source project files from another checkout, generated cache, remote clone, or memory unless the user explicitly changes this rule.
- Archive source status: it contains the app source, tests, `PLAN.md`, and `AgentNotes.md`, and it has uncommitted Phase 7.2 work. Treat it as the authorized restore source, while still preserving its dirty work exactly.
- Reference checkout branch and remote evidence: `main...origin/main`, remote `https://github.com/JamesPriceZV/Agenic-Load-Balancer.git`.
- Reference checkout dirty state: modified `Agenic Load-Balancer/ContentView.swift`, `Agenic Load-Balancer/Models/AgenicModels.swift`, `Agenic Load-Balancer/Services/RunDispatcher.swift`, `Agenic Load-Balancer/Services/SnapshotArchive.swift`, `AgentNotes.md`; untracked `Agenic Load-Balancer/Services/RunSummary.swift` and `Agenic Load-BalancerTests/RunSummaryTests.swift`.
- Phase dependency: Phase 7.2 is implemented in the reference checkout but not checkpointed in the inspected evidence. Before Phase 7.3 work begins, validate and checkpoint Phase 7.2 or intentionally carry it forward on a feature branch.

## Existing System Map From Repo Evidence

- `Agenic Load-Balancer/Models/AgenicModels.swift`: SwiftData schema and shared enums. Current models include projects, prompt threads/messages, provider profiles, command profiles, usage ledgers, routing decisions, run outcomes, coordination events, snapshots, and Keychain references.
- `Agenic Load-Balancer/Services/CoordinationAndSync.swift`: app-wide service singletons, `ProjectCoordinationActor`, AgentNotes generation/reconciliation, NSFileCoordinator-safe reads/writes, Cloud sync, restore, provider setup, and Keychain helpers.
- `Agenic Load-Balancer/Services/RoutingEngine.swift`: deterministic provider ranking from prompt signals, provider state, usage pressure, accuracy, latency, cost, and AgentNotes conflict warnings.
- `Agenic Load-Balancer/Services/RunDispatcher.swift`: approval-backed run lifecycle, prompt composition, AgentNotes excerpt injection, streaming logs, usage/outcome persistence, git checkpoint stamping, and Phase 7.2 AI summary status.
- `Agenic Load-Balancer/Services/FoundationModels.swift`: Foundation Models availability abstraction, in-process adapter, runner, session driver, and composite runner routing.
- `Agenic Load-Balancer/Services/RunSummary.swift`: Phase 7.2 structured outcome summary surface in the dirty reference checkout.
- `Agenic Load-Balancer/Services/SnapshotPipeline.swift` and `SnapshotArchive.swift`: checksummed snapshot build, preview, merge, replace, DTO archive round-trip.
- `Agenic Load-Balancer/Services/AgentAdapters.swift`: provider health probing, CLI adapter factory, command profile overrides, and generic CLI command construction.
- `Agenic Load-Balancer/ContentView.swift`: dashboard, prompt router, approval sheet, provider setup, restore center, and AgentNotes UI live in one large SwiftUI file. New Phase 7.3+ UI should create focused view files if the Xcode project supports file references cleanly.
- Existing validation command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test
```

Expected result after each completed phase: `** TEST SUCCEEDED **`.

## Source Truth And Safety Rules

- Before code edits, restore or locate the real canonical checkout. Do not implement into the skeletal requested root unless the missing source tree is intentionally being reconstructed.
- Preserve unrelated dirty work. The reference checkout has uncommitted Phase 7.2 changes that must not be overwritten.
- Restore missing project files and `PLAN.md` only from `/Users/zincoverde/Documents/OneDrive-OLD/4_XcodeProjects/Agenic Load-Balancer` unless the user explicitly approves another source.
- Keep deterministic code canonical. Foundation Models can enrich summaries, command interpretation, merge proposals, and tie-break explanations, but the app must still have deterministic fallbacks.
- Tool-calling tools must be action-gated. Tools may rank, probe, read metrics, and draft actions directly. Tools that dispatch runs, create snapshots, reconcile files, write notes, commit, push, delete, or mutate CloudKit records must return a proposed action unless the user has already approved the exact operation in the app UI.
- Cross-machine sync must be lossless. "Perfect conflict resolution" means no silent data loss: deterministic merges for known commutative operations, content-addressed snapshots for rollback, and explicit conflict records for non-commutative edits that need human review.
- All model features need tests for unavailable Apple Intelligence, framework-unavailable builds, generation failure, cancellation, malformed tool output, and success.

## File Structure To Create Or Modify

### Phase 7.3 Files

- Create: `Agenic Load-Balancer/Services/CommandBarActions.swift`
  - Plain Sendable request/result values and `CommandBarActionExecutor` actor that wraps ranking, dispatch draft creation, provider probing, snapshot creation draft/apply, AgentNotes reconciliation draft/apply, and dashboard metric reads.
- Create: `Agenic Load-Balancer/Services/CommandBarTools.swift`
  - Foundation Models `Tool<Arguments, Output>` definitions for `rankAgents`, `dispatchRun`, `probeProviders`, `createSnapshot`, `reconcileAgentNotes`, and `readDashboardMetrics`.
- Create: `Agenic Load-Balancer/Services/NaturalLanguageCommandBar.swift`
  - `NaturalLanguageCommandBarModel`, tool-session factory, transcript state, availability/fallback handling, command result rendering values, and approval handoff state.
- Create: `Agenic Load-Balancer/Views/CommandBarView.swift`
  - SwiftUI command bar/palette surface, prompt field, result list, approval buttons, and transcript disclosure.
- Modify: `Agenic Load-Balancer/ContentView.swift`
  - Add toolbar/menu entry for the command bar and wire the view to current SwiftData query snapshots.
- Test: `Agenic Load-BalancerTests/CommandBarActionTests.swift`
- Test: `Agenic Load-BalancerTests/CommandBarToolTests.swift`

### Phase 7.4 Files

- Create: `Agenic Load-Balancer/Services/AgentNotesIntelligence.swift`
  - `AgentNotesPreflightSummary`, `AgentNotesMergeProposal`, `AgentNotesIntelligencing` protocol, live Foundation Models implementation, noop implementation, and scripted test implementation.
- Modify: `Agenic Load-Balancer/Services/CoordinationAndSync.swift`
  - Add full-content AgentNotes read helpers, relevance-oriented preflight summary hooks, and merge proposal application surfaces that never write without confirmation.
- Modify: `Agenic Load-Balancer/Services/RunDispatcher.swift`
  - Accept preflight summary text in addition to raw excerpt, and embed the summary above the user prompt.
- Modify: `Agenic Load-Balancer/ContentView.swift` or create `Agenic Load-Balancer/Views/AgentNotesReconciliationView.swift`
  - Show relevant active claims, merge proposal diff, checksums, and approval controls.
- Test: `Agenic Load-BalancerTests/AgentNotesIntelligenceTests.swift`
- Test: extend `Agenic Load-BalancerTests/CoordinationCheckpointTests.swift`

### Phase 7.5 Files

- Create: `Agenic Load-Balancer/Services/RoutingTieBreaker.swift`
  - `RoutingTieBreak`, `RoutingTieBreaking`, `LiveFoundationModelsRoutingTieBreaker`, `NoopRoutingTieBreaker`, and scripted tests.
- Modify: `Agenic Load-Balancer/Services/RoutingEngine.swift`
  - Add a deterministic close-score detector and a plain `RoutingRecommendation` output that can carry optional tie-break metadata without changing the canonical score math.
- Modify: `Agenic Load-Balancer/ContentView.swift`
  - Show "on-device tie-break applied" rationale when available and make the original numeric scores visible.
- Test: `Agenic Load-BalancerTests/RoutingTieBreakerTests.swift`
- Test: extend `Agenic Load-BalancerTests/Agenic_Load_BalancerTests.swift` or create focused routing tests if none cover this behavior cleanly.

### Phase 7.6 Files

- Modify: `Agenic Load-Balancer/Models/AgenicModels.swift`
  - Add CloudKit-compatible models for goals, autonomous plans, tasks, machine peers, operation logs, conflict records, autonomy policies, validation gates, and audit trail entries.
- Create: `Agenic Load-Balancer/Services/AutonomousProjectManager.swift`
  - Goal intake, task graph planning, policy checks, provider selection, dispatch orchestration, validation scheduling, checkpointing, and stop/resume.
- Create: `Agenic Load-Balancer/Services/AutonomyPolicy.swift`
  - Safety levels, allowed roots, protected paths, destructive command rules, branch/commit rules, approval requirements, and budget limits.
- Create: `Agenic Load-Balancer/Services/ConflictResolutionEngine.swift`
  - Operation-log merge, vector-clock comparison, conflict classification, deterministic resolution for commutative records, and human-review records for ambiguous file/content conflicts.
- Create: `Agenic Load-Balancer/Services/MachineSyncCoordinator.swift`
  - Peer identity, last-seen state, CloudKit record health, snapshot verification, and sync-repair recommendations.
- Create: `Agenic Load-Balancer/Services/ValidationGateRunner.swift`
  - Build/test command registry, scripted validation runner, result capture, and policy evaluation.
- Create: `Agenic Load-Balancer/Views/AutonomyControlCenterView.swift`
  - Goal entry, autonomy level selector, task graph board, machine sync health, conflict center, validation log, and audit trail.
- Test: `Agenic Load-BalancerTests/AutonomyPolicyTests.swift`
- Test: `Agenic Load-BalancerTests/ConflictResolutionEngineTests.swift`
- Test: `Agenic Load-BalancerTests/AutonomousProjectManagerTests.swift`
- Test: `Agenic Load-BalancerTests/MachineSyncCoordinatorTests.swift`
- Test: `Agenic Load-BalancerTests/ValidationGateRunnerTests.swift`

## Phase 0: Repair Execution Ground Before Phase 7.3

### Task 0.1: Confirm The Canonical Checkout And Authorized Archive Source

**Files:**
- Inspect: `/Users/zincoverde/Library/CloudStorage/OneDrive-Personal/4_XcodeProjects/Agenic Load-Balancer`
- Inspect: `/Users/zincoverde/Documents/OneDrive-OLD/4_XcodeProjects/Agenic Load-Balancer`
- Modify only after root decision: `AgentNotes.md`, `PLAN.md`, `AgentPlan.md`

- [ ] **Step 1: Run root checks from the requested path**

```bash
pwd -P
git rev-parse --show-toplevel
git status --short --branch
find . -maxdepth 3 -type f -print
```

Expected before repair if the inspected state has not changed:

```text
/Users/zincoverde/Library/CloudStorage/OneDrive-Personal/4_XcodeProjects/Agenic Load-Balancer
fatal: not a git repository (or any of the parent directories): .git
fatal: not a git repository (or any of the parent directories): .git
./AgentPlan.md
./Agenic Load-Balancer.xcodeproj/project.xcworkspace/contents.xcworkspacedata
```

- [ ] **Step 2: Locate the authorized archive source**

```bash
find /Users/zincoverde/Library/CloudStorage/OneDrive-Personal/4_XcodeProjects -maxdepth 3 -name .git -type d -print
find /Users/zincoverde/Documents -maxdepth 5 -path '*Agenic Load-Balancer/.git' -type d -print
```

Expected if only the reference checkout exists:

```text
/Users/zincoverde/Documents/OneDrive-OLD/4_XcodeProjects/Agenic Load-Balancer/.git
```

- [ ] **Step 3: Restore missing files from the authorized archive source when the requested root is skeletal**

Use this only after confirming the requested root still lacks source files and `PLAN.md`. Preserve the current `AgentPlan.md`.

```bash
ARCHIVE="/Users/zincoverde/Documents/OneDrive-OLD/4_XcodeProjects/Agenic Load-Balancer"
TARGET="/Users/zincoverde/Library/CloudStorage/OneDrive-Personal/4_XcodeProjects/Agenic Load-Balancer"
rsync -a --exclude 'AgentPlan.md' "$ARCHIVE"/ "$TARGET"/
```

Expected:

```text
The target root contains .git, PLAN.md, AgentNotes.md, source folders, tests, and the existing AgentPlan.md.
```

- [ ] **Step 4: Choose the execution root**

Use one of these outcomes:

```text
Outcome A: The OneDrive-Personal root has been restored from the authorized archive source and contains .git, source files, AgentNotes.md, PLAN.md, and AgentPlan.md. Execute phases there.
Outcome B: The user explicitly redirects work to the OneDrive-OLD archive source. Execute phases there after preserving dirty Phase 7.2 work.
Outcome C: The archive source is unavailable or incomplete. Stop and ask the user for a new authorized source before copying project files or PLAN.md from anywhere else.
```

- [ ] **Step 5: Preserve Phase 7.2 dirty work before starting**

```bash
git status --short --branch
git diff -- 'Agenic Load-Balancer/Services/RunSummary.swift' 'Agenic Load-Balancer/Services/RunDispatcher.swift' 'Agenic Load-Balancer/Models/AgenicModels.swift' 'Agenic Load-Balancer/ContentView.swift' 'Agenic Load-Balancer/Services/SnapshotArchive.swift' 'Agenic Load-BalancerTests/RunSummaryTests.swift' AgentNotes.md
```

Expected if the reference checkout remains dirty:

```text
Modified Phase 7.2 files are visible and must be committed, stashed with a named stash, or carried forward on a feature branch before Phase 7.3 edits overlap them.
```

### Task 0.2: Validate Or Checkpoint Phase 7.2

**Files:**
- Modify: `AgentNotes.md`
- Modify: `PLAN.md`
- Existing dirty files from Phase 7.2

- [ ] **Step 1: Run the macOS test gate**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 2: Record Phase 7.2 validation**

Add an `AgentNotes.md` checkpoint entry with this content shape:

```markdown
- [checkpointed] Phase 7.2 / Foundation Models / Structured outcome classification: Validate `@Generable RunSummary`
  Assignee: <agent name>
  Detail: Validated the Phase 7.2 Foundation Models run-summary path, including additive `RunOutcomeRecord` fields, archive DTO round-trip, dispatcher AI summary status, and UI summary panel.
  Run: local validation on <date>
  Commit: <commit sha after commit>
  Conflict: none
  Validation: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test` returned ** TEST SUCCEEDED **.
```

- [ ] **Step 3: Update `PLAN.md` handoff state**

Replace the Phase 7.2 "next recommended" or pending language with:

```markdown
- Phase 7.2 status: validated and checkpointed. Structured `RunSummary` classification is now the baseline for Phase 7.3+ command actions, dashboard metric reads, and routing tie-break context.
- Next recommended implementation unit: Phase 7.3, natural-language tool-calling command bar.
```

- [ ] **Step 4: Commit Phase 7.2 separately**

```bash
git add 'Agenic Load-Balancer/Services/RunSummary.swift' 'Agenic Load-BalancerTests/RunSummaryTests.swift' 'Agenic Load-Balancer/Models/AgenicModels.swift' 'Agenic Load-Balancer/Services/RunDispatcher.swift' 'Agenic Load-Balancer/Services/SnapshotArchive.swift' 'Agenic Load-Balancer/ContentView.swift' AgentNotes.md PLAN.md
git commit -m "Wire Foundation Models run summaries"
```

Expected:

```text
[main <sha>] Wire Foundation Models run summaries
```

## Phase 7.3: Natural-Language Tool-Calling Command Bar

### Task 1: Add Shared Command Action Values

**Files:**
- Create: `Agenic Load-Balancer/Services/CommandBarActions.swift`
- Test: `Agenic Load-BalancerTests/CommandBarActionTests.swift`

- [ ] **Step 1: Create the request and result types**

Add:

```swift
import Foundation

enum CommandBarActionKind: String, CaseIterable, Sendable, Codable, Hashable {
    case rankAgents
    case dispatchRun
    case probeProviders
    case createSnapshot
    case reconcileAgentNotes
    case readDashboardMetrics
}

enum CommandBarApprovalRequirement: String, Sendable, Codable, Hashable {
    case none
    case userApprovalRequired
    case blockedByPolicy
}

struct CommandBarActionResult: Sendable, Codable, Hashable {
    var kind: CommandBarActionKind
    var title: String
    var summary: String
    var detailLines: [String]
    var approvalRequirement: CommandBarApprovalRequirement
    var approvalID: String?
    var createdAt: Date

    init(
        kind: CommandBarActionKind,
        title: String,
        summary: String,
        detailLines: [String] = [],
        approvalRequirement: CommandBarApprovalRequirement = .none,
        approvalID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.kind = kind
        self.title = title
        self.summary = summary
        self.detailLines = detailLines
        self.approvalRequirement = approvalRequirement
        self.approvalID = approvalID
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: Add tests for approval semantics**

```swift
import Testing
@testable import Agenic_Load_Balancer

@Suite("Phase 7.3 command action values")
struct CommandBarActionTests {
    @Test func dispatchResultRequiresApprovalIDWhenApprovalIsRequired() {
        let result = CommandBarActionResult(
            kind: .dispatchRun,
            title: "Dispatch Codex",
            summary: "Prepared run for approval.",
            approvalRequirement: .userApprovalRequired,
            approvalID: "approval-1"
        )

        #expect(result.approvalRequirement == .userApprovalRequired)
        #expect(result.approvalID == "approval-1")
    }

    @Test func readOnlyResultNeedsNoApproval() {
        let result = CommandBarActionResult(
            kind: .readDashboardMetrics,
            title: "Dashboard metrics",
            summary: "Read six provider metrics.",
            detailLines: ["Availability: 100%"]
        )

        #expect(result.approvalRequirement == .none)
        #expect(result.detailLines == ["Availability: 100%"])
    }
}
```

- [ ] **Step 3: Run the focused tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test -only-testing:Agenic_Load_BalancerTests/CommandBarActionTests
```

Expected:

```text
** TEST SUCCEEDED **
```

### Task 2: Add The CommandBarActionExecutor Actor

**Files:**
- Modify: `Agenic Load-Balancer/Services/CommandBarActions.swift`
- Test: `Agenic Load-BalancerTests/CommandBarActionTests.swift`

- [ ] **Step 1: Add executor input snapshots**

Add:

```swift
struct CommandBarContext: Sendable {
    var prompt: String
    var mode: AgentExecutionMode
    var projectID: String?
    var projectName: String?
    var projectRootPath: String?
    var providers: [AgentProviderSnapshot]
    var usage: [UsageSnapshot]
    var accuracy: [AccuracySnapshot]
    var coordinationEvents: [CoordinationEventSnapshot]

    init(
        prompt: String,
        mode: AgentExecutionMode,
        projectID: String? = nil,
        projectName: String? = nil,
        projectRootPath: String? = nil,
        providers: [AgentProviderSnapshot],
        usage: [UsageSnapshot] = [],
        accuracy: [AccuracySnapshot] = [],
        coordinationEvents: [CoordinationEventSnapshot] = []
    ) {
        self.prompt = prompt
        self.mode = mode
        self.projectID = projectID
        self.projectName = projectName
        self.projectRootPath = projectRootPath
        self.providers = providers
        self.usage = usage
        self.accuracy = accuracy
        self.coordinationEvents = coordinationEvents
    }
}
```

- [ ] **Step 2: Add read-only action methods**

Add:

```swift
actor CommandBarActionExecutor {
    private let routingEngine: RoutingEngine
    private let healthMonitor: ProviderHealthMonitor
    private let coordination: ProjectCoordinationActor

    init(
        routingEngine: RoutingEngine = AppServices.routingEngine,
        healthMonitor: ProviderHealthMonitor = AppServices.healthMonitor,
        coordination: ProjectCoordinationActor = AppServices.coordination
    ) {
        self.routingEngine = routingEngine
        self.healthMonitor = healthMonitor
        self.coordination = coordination
    }

    func rankAgents(context: CommandBarContext, limit: Int = 5) async -> CommandBarActionResult {
        let ranked = await routingEngine.rank(
            prompt: context.prompt,
            mode: context.mode,
            providers: context.providers,
            usage: context.usage,
            accuracy: context.accuracy,
            coordinationEvents: context.coordinationEvents
        )
        let limited = Array(ranked.prefix(max(1, min(limit, 10))))
        return CommandBarActionResult(
            kind: .rankAgents,
            title: "Ranked \(limited.count) agent(s)",
            summary: limited.first.map { "\($0.providerName) leads at \($0.totalScore.percentString)." } ?? "No enabled providers were available.",
            detailLines: limited.map { "\($0.providerName): \($0.totalScore.percentString) - \($0.rationale)" }
        )
    }

    func readDashboardMetrics(usage: [UsageSnapshot], accuracy: [AccuracySnapshot]) -> CommandBarActionResult {
        let lines = usage.map { snapshot in
            "\(snapshot.providerID): pressure \(snapshot.limitPressure.percentString), success \(snapshot.successRate.percentString), latency \(Int(snapshot.averageLatencySeconds))s"
        } + accuracy.map { snapshot in
            "\(snapshot.providerID): accuracy \(snapshot.averageScore.percentString) across \(snapshot.totalRatedRuns) rated run(s)"
        }
        return CommandBarActionResult(
            kind: .readDashboardMetrics,
            title: "Dashboard metrics",
            summary: "Read \(lines.count) dashboard signal(s).",
            detailLines: lines
        )
    }
}
```

- [ ] **Step 3: Add mutating action drafts**

Add methods whose first implementation returns proposals instead of writing:

```swift
extension CommandBarActionExecutor {
    func dispatchRunDraft(context: CommandBarContext, providerID: String?) async -> CommandBarActionResult {
        let ranked = await routingEngine.rank(
            prompt: context.prompt,
            mode: context.mode,
            providers: context.providers,
            usage: context.usage,
            accuracy: context.accuracy,
            coordinationEvents: context.coordinationEvents
        )
        let selected = providerID.flatMap { id in ranked.first { $0.providerID == id } } ?? ranked.first
        guard let selected else {
            return CommandBarActionResult(
                kind: .dispatchRun,
                title: "No dispatch target",
                summary: "No enabled provider can run this request.",
                approvalRequirement: .blockedByPolicy
            )
        }
        return CommandBarActionResult(
            kind: .dispatchRun,
            title: "Approve dispatch to \(selected.providerName)",
            summary: "Prepared \(context.mode.label) run for \(selected.providerName).",
            detailLines: [selected.rationale, selected.limitImpact],
            approvalRequirement: .userApprovalRequired,
            approvalID: "dispatch:\(selected.providerID):\(UUID().uuidString)"
        )
    }

    func createSnapshotDraft(scope: String) -> CommandBarActionResult {
        CommandBarActionResult(
            kind: .createSnapshot,
            title: "Approve snapshot",
            summary: "Create a checksummed snapshot archive for \(scope).",
            approvalRequirement: .userApprovalRequired,
            approvalID: "snapshot:\(UUID().uuidString)"
        )
    }

    func reconcileAgentNotesDraft(projectName: String, rootPath: String, events: [CoordinationEventSnapshot]) async -> CommandBarActionResult {
        do {
            let result = try await coordination.reconcile(projectName: projectName, rootPath: rootPath, events: events)
            return CommandBarActionResult(
                kind: .reconcileAgentNotes,
                title: "AgentNotes reconciliation",
                summary: String(describing: result.state),
                detailLines: [result.fileURL.path],
                approvalRequirement: result.requiresAttention ? .userApprovalRequired : .none,
                approvalID: result.requiresAttention ? "agentnotes:\(UUID().uuidString)" : nil
            )
        } catch {
            return CommandBarActionResult(
                kind: .reconcileAgentNotes,
                title: "AgentNotes reconciliation failed",
                summary: error.localizedDescription,
                approvalRequirement: .blockedByPolicy
            )
        }
    }
}
```

- [ ] **Step 4: Add tests for draft gating**

```swift
@Test func snapshotDraftRequiresUserApproval() async {
    let executor = CommandBarActionExecutor()
    let result = await executor.createSnapshotDraft(scope: "full project")

    #expect(result.kind == .createSnapshot)
    #expect(result.approvalRequirement == .userApprovalRequired)
    #expect(result.approvalID?.hasPrefix("snapshot:") == true)
}
```

### Task 3: Add Foundation Models Tool Definitions

**Files:**
- Create: `Agenic Load-Balancer/Services/CommandBarTools.swift`
- Test: `Agenic Load-BalancerTests/CommandBarToolTests.swift`

- [ ] **Step 1: Add framework-gated tools**

```swift
import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
struct RankAgentsTool: Tool {
    let name = "rankAgents"
    let description = "Ranks available coding agents for the current prompt."
    let executor: CommandBarActionExecutor
    let contextProvider: @Sendable () async -> CommandBarContext

    @Generable
    struct Arguments {
        @Guide(description: "Maximum number of agents to return, from 1 through 10.")
        let limit: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let context = await contextProvider()
        let result = await executor.rankAgents(context: context, limit: arguments.limit)
        return CommandBarToolFormatter.format(result)
    }
}

@available(macOS 26.0, *)
struct ReadDashboardMetricsTool: Tool {
    let name = "readDashboardMetrics"
    let description = "Reads current provider usage, limit, success, latency, and accuracy dashboard metrics."
    let metricsProvider: @Sendable () async -> ([UsageSnapshot], [AccuracySnapshot])

    @Generable
    struct Arguments {
        @Guide(description: "Provider identifier to filter by, or empty for all providers.")
        let providerID: String
    }

    func call(arguments: Arguments) async throws -> String {
        let (usage, accuracy) = await metricsProvider()
        let filteredUsage = arguments.providerID.isEmpty ? usage : usage.filter { $0.providerID == arguments.providerID }
        let filteredAccuracy = arguments.providerID.isEmpty ? accuracy : accuracy.filter { $0.providerID == arguments.providerID }
        let result = CommandBarActionExecutor().readDashboardMetrics(usage: filteredUsage, accuracy: filteredAccuracy)
        return CommandBarToolFormatter.format(result)
    }
}
#endif

enum CommandBarToolFormatter {
    static func format(_ result: CommandBarActionResult) -> String {
        ([result.title, result.summary] + result.detailLines).joined(separator: "\n")
    }
}
```

- [ ] **Step 2: Add mutating tools as draft-only tools**

```swift
#if canImport(FoundationModels)
@available(macOS 26.0, *)
struct DispatchRunTool: Tool {
    let name = "dispatchRun"
    let description = "Prepares a provider run for user approval; it does not start the run by itself."
    let executor: CommandBarActionExecutor
    let contextProvider: @Sendable () async -> CommandBarContext

    @Generable
    struct Arguments {
        @Guide(description: "Provider identifier to dispatch, or empty to use the top-ranked provider.")
        let providerID: String
    }

    func call(arguments: Arguments) async throws -> String {
        let context = await contextProvider()
        let result = await executor.dispatchRunDraft(
            context: context,
            providerID: arguments.providerID.isEmpty ? nil : arguments.providerID
        )
        return CommandBarToolFormatter.format(result)
    }
}

@available(macOS 26.0, *)
struct CreateSnapshotTool: Tool {
    let name = "createSnapshot"
    let description = "Prepares a checksummed snapshot action for user approval."
    let executor: CommandBarActionExecutor

    @Generable
    struct Arguments {
        @Guide(description: "Snapshot scope label, such as full project or current project.")
        let scope: String
    }

    func call(arguments: Arguments) async throws -> String {
        CommandBarToolFormatter.format(executor.createSnapshotDraft(scope: arguments.scope))
    }
}
#endif
```

- [ ] **Step 3: Add tool availability tests using formatter and draft behavior**

```swift
@Suite("Phase 7.3 command tools")
struct CommandBarToolTests {
    @Test func formatterIncludesTitleSummaryAndDetails() {
        let result = CommandBarActionResult(
            kind: .rankAgents,
            title: "Ranked 1 agent",
            summary: "Codex leads.",
            detailLines: ["Codex: 92%"]
        )

        #expect(CommandBarToolFormatter.format(result) == "Ranked 1 agent\nCodex leads.\nCodex: 92%")
    }

    @Test func dispatchToolDescriptionIsDraftOnly() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let tool = DispatchRunTool(
                executor: CommandBarActionExecutor(),
                contextProvider: {
                    CommandBarContext(
                        prompt: "Run tests",
                        mode: .testBuild,
                        providers: []
                    )
                }
            )
            #expect(tool.description.contains("does not start"))
        }
        #endif
    }
}
```

### Task 4: Add NaturalLanguageCommandBarModel

**Files:**
- Create: `Agenic Load-Balancer/Services/NaturalLanguageCommandBar.swift`
- Test: extend `Agenic Load-BalancerTests/CommandBarToolTests.swift`

- [ ] **Step 1: Add model states and fallback**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class NaturalLanguageCommandBarModel {
    enum State: Sendable, Equatable {
        case idle
        case unavailable(String)
        case responding
        case completed(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastResult: String = ""
    private let availabilityChecker: any FoundationModelsAvailabilityChecking
    private let executor: CommandBarActionExecutor

    init(
        availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker(),
        executor: CommandBarActionExecutor = CommandBarActionExecutor()
    ) {
        self.availabilityChecker = availabilityChecker
        self.executor = executor
    }

    func submit(
        prompt: String,
        contextProvider: @escaping @Sendable () async -> CommandBarContext,
        metricsProvider: @escaping @Sendable () async -> ([UsageSnapshot], [AccuracySnapshot])
    ) {
        let availability = availabilityChecker.currentAvailability()
        guard availability.isAvailable else {
            state = .unavailable(availability.message)
            return
        }
        state = .responding
        Task {
            do {
                let response = try await Self.respondWithFoundationModels(
                    prompt: prompt,
                    executor: executor,
                    contextProvider: contextProvider,
                    metricsProvider: metricsProvider
                )
                await MainActor.run {
                    self.lastResult = response
                    self.state = .completed(response)
                }
            } catch {
                await MainActor.run {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Add the gated session method**

```swift
extension NaturalLanguageCommandBarModel {
    nonisolated static func respondWithFoundationModels(
        prompt: String,
        executor: CommandBarActionExecutor,
        contextProvider: @escaping @Sendable () async -> CommandBarContext,
        metricsProvider: @escaping @Sendable () async -> ([UsageSnapshot], [AccuracySnapshot])
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let tools: [any Tool] = [
                RankAgentsTool(executor: executor, contextProvider: contextProvider),
                DispatchRunTool(executor: executor, contextProvider: contextProvider),
                CreateSnapshotTool(executor: executor),
                ReadDashboardMetricsTool(metricsProvider: metricsProvider),
            ]
            let session = LanguageModelSession(
                tools: tools,
                instructions: Instructions {
                    "You operate the Agenic Load-Balancer command bar."
                    "Use tools for current app data and actions."
                    "Never claim a draft action has already executed."
                    "Return concise next steps after tool results."
                }
            )
            let response = try await session.respond {
                Prompt(prompt)
            }
            return response.content
        }
        throw RunSummaryError.unavailable(FoundationModelsAvailability.frameworkUnavailable.message)
        #else
        throw RunSummaryError.unavailable(FoundationModelsAvailability.frameworkUnavailable.message)
        #endif
    }
}
```

- [ ] **Step 3: Test unavailable state**

```swift
@MainActor
@Test func commandBarUnavailableWhenFoundationModelsUnavailable() async {
    let model = NaturalLanguageCommandBarModel(
        availabilityChecker: StubFoundationModelsAvailabilityChecker(.frameworkUnavailable)
    )

    model.submit(
        prompt: "rank agents",
        contextProvider: { CommandBarContext(prompt: "rank agents", mode: .recommendOnly, providers: []) },
        metricsProvider: { ([], []) }
    )

    #expect(model.state == .unavailable(FoundationModelsAvailability.frameworkUnavailable.message))
}
```

### Task 5: Add The SwiftUI Command Bar

**Files:**
- Create: `Agenic Load-Balancer/Views/CommandBarView.swift`
- Modify: `Agenic Load-Balancer/ContentView.swift`

- [ ] **Step 1: Create the command bar view**

```swift
import SwiftUI
import SwiftData

struct CommandBarView: View {
    @State private var prompt = ""
    @State private var model = NaturalLanguageCommandBarModel()
    let contextProvider: @Sendable () async -> CommandBarContext
    let metricsProvider: @Sendable () async -> ([UsageSnapshot], [AccuracySnapshot])

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                TextField("Ask the command bar", text: $prompt)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                Button("Run", systemImage: "arrow.up.circle.fill", action: submit)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            resultView
        }
        .padding(16)
        .frame(minWidth: 560)
    }

    @ViewBuilder
    private var resultView: some View {
        switch model.state {
        case .idle:
            Text("Ready")
                .foregroundStyle(.secondary)
        case .responding:
            ProgressView("Thinking")
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .completed(let result):
            Text(result)
                .textSelection(.enabled)
        case .failed(let reason):
            Label(reason, systemImage: "xmark.octagon")
                .foregroundStyle(.red)
        }
    }

    private func submit() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.submit(prompt: trimmed, contextProvider: contextProvider, metricsProvider: metricsProvider)
    }
}
```

- [ ] **Step 2: Wire it into `ContentView.swift`**

Add a sheet state near the root `ContentView` state:

```swift
@State private var showingCommandBar = false
```

Add a toolbar button:

```swift
.toolbar {
    Button("Command Bar", systemImage: "command") {
        showingCommandBar = true
    }
}
```

Add the sheet:

```swift
.sheet(isPresented: $showingCommandBar) {
    CommandBarView(
        contextProvider: {
            CommandBarContext(
                prompt: "",
                mode: .recommendOnly,
                projectID: selectedProject?.identifier,
                projectName: selectedProject?.name,
                projectRootPath: selectedProject?.rootPath,
                providers: providers.map { $0.snapshot() },
                usage: UsageSnapshotBuilder.build(providers: providers.map { $0.snapshot() }, ledgers: usageLedgers, outcomes: outcomes),
                accuracy: AccuracySnapshotBuilder.build(outcomes: outcomes),
                coordinationEvents: coordinationEvents.map { $0.snapshot() }
            )
        },
        metricsProvider: {
            (
                UsageSnapshotBuilder.build(providers: providers.map { $0.snapshot() }, ledgers: usageLedgers, outcomes: outcomes),
                AccuracySnapshotBuilder.build(outcomes: outcomes)
            )
        }
    )
}
```

If `ContentView` does not have `selectedProject`, `usageLedgers`, or `outcomes` in scope with these exact names, use the existing `@Query` names from the dashboard and prompt router. Do not add duplicate queries when the data is already loaded at the root view.

- [ ] **Step 3: Run full tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test
```

Expected:

```text
** TEST SUCCEEDED **
```

## Phase 7.4: Intelligent AgentNotes Preflight And AI-Assisted Reconciliation

### Task 6: Add AgentNotes Intelligence Values

**Files:**
- Create: `Agenic Load-Balancer/Services/AgentNotesIntelligence.swift`
- Test: `Agenic Load-BalancerTests/AgentNotesIntelligenceTests.swift`

- [ ] **Step 1: Add plain value types**

```swift
import Foundation

struct AgentNotesPreflightSummary: Sendable, Codable, Hashable {
    var relevantActiveClaims: [String]
    var blockingConflicts: [String]
    var suggestedClaim: String
    var promptInjectionText: String
}

struct AgentNotesMergeProposal: Sendable, Codable, Hashable {
    var mergedContent: String
    var retainedLocalLines: [String]
    var retainedGeneratedLines: [String]
    var unresolvedConflicts: [String]
    var explanation: String
}

enum AgentNotesIntelligenceError: Error, Sendable, LocalizedError, Equatable {
    case unavailable(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "AgentNotes intelligence unavailable: \(reason)"
        case .generationFailed(let reason): "AgentNotes intelligence failed: \(reason)"
        }
    }
}

protocol AgentNotesIntelligencing: Sendable {
    func summarizePreflight(agentNotes: String, prompt: String, mode: AgentExecutionMode) async throws -> AgentNotesPreflightSummary
    func proposeMerge(localContent: String, generatedContent: String) async throws -> AgentNotesMergeProposal
}
```

- [ ] **Step 2: Add noop and scripted implementations**

```swift
struct NoopAgentNotesIntelligence: AgentNotesIntelligencing {
    let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func summarizePreflight(agentNotes: String, prompt: String, mode: AgentExecutionMode) async throws -> AgentNotesPreflightSummary {
        throw AgentNotesIntelligenceError.unavailable(reason)
    }

    func proposeMerge(localContent: String, generatedContent: String) async throws -> AgentNotesMergeProposal {
        throw AgentNotesIntelligenceError.unavailable(reason)
    }
}

struct ScriptedAgentNotesIntelligence: AgentNotesIntelligencing {
    var summary: AgentNotesPreflightSummary
    var proposal: AgentNotesMergeProposal

    func summarizePreflight(agentNotes: String, prompt: String, mode: AgentExecutionMode) async throws -> AgentNotesPreflightSummary {
        summary
    }

    func proposeMerge(localContent: String, generatedContent: String) async throws -> AgentNotesMergeProposal {
        proposal
    }
}
```

- [ ] **Step 3: Add tests for fallback behavior**

```swift
@Suite("Phase 7.4 AgentNotes intelligence")
struct AgentNotesIntelligenceTests {
    @Test func noopPreflightThrowsUnavailableReason() async {
        let intelligence = NoopAgentNotesIntelligence(reason: "Apple Intelligence disabled")

        await #expect(throws: AgentNotesIntelligenceError.unavailable("Apple Intelligence disabled")) {
            _ = try await intelligence.summarizePreflight(
                agentNotes: "# AgentNotes",
                prompt: "Fix tests",
                mode: .repairDebug
            )
        }
    }

    @Test func scriptedMergeReturnsUnresolvedConflictList() async throws {
        let intelligence = ScriptedAgentNotesIntelligence(
            summary: AgentNotesPreflightSummary(
                relevantActiveClaims: ["Phase 7.2 pending"],
                blockingConflicts: [],
                suggestedClaim: "Claim Phase 7.3",
                promptInjectionText: "Relevant active claim: Phase 7.2 pending"
            ),
            proposal: AgentNotesMergeProposal(
                mergedContent: "merged",
                retainedLocalLines: ["local"],
                retainedGeneratedLines: ["generated"],
                unresolvedConflicts: ["same section edited differently"],
                explanation: "Manual review needed."
            )
        )

        let proposal = try await intelligence.proposeMerge(localContent: "local", generatedContent: "generated")
        #expect(proposal.unresolvedConflicts == ["same section edited differently"])
    }
}
```

### Task 7: Add Live Foundation Models AgentNotes Intelligence

**Files:**
- Modify: `Agenic Load-Balancer/Services/AgentNotesIntelligence.swift`

- [ ] **Step 1: Add `@Generable` output shapes**

```swift
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct GeneratedAgentNotesPreflightSummary: Sendable {
    @Guide(description: "Active AgentNotes claims relevant to the user's prompt.")
    var relevantActiveClaims: [String]

    @Guide(description: "Blocking conflicts the user or agent must resolve before dispatch.")
    var blockingConflicts: [String]

    @Guide(description: "A concise claim line the next agent should record before editing.")
    var suggestedClaim: String

    @Guide(description: "Short text safe to inject into an agent prompt.")
    var promptInjectionText: String
}

@available(macOS 26.0, *)
@Generable
struct GeneratedAgentNotesMergeProposal: Sendable {
    @Guide(description: "Full merged AgentNotes content preserving both local and generated facts.")
    var mergedContent: String

    @Guide(description: "Important local lines retained in the merge.")
    var retainedLocalLines: [String]

    @Guide(description: "Important generated lines retained in the merge.")
    var retainedGeneratedLines: [String]

    @Guide(description: "Conflicts that cannot be resolved safely.")
    var unresolvedConflicts: [String]

    @Guide(description: "Concise explanation of the merge strategy.")
    var explanation: String
}
#endif
```

- [ ] **Step 2: Add the live implementation**

```swift
#if canImport(FoundationModels)
@available(macOS 26.0, *)
struct LiveFoundationModelsAgentNotesIntelligence: AgentNotesIntelligencing {
    func summarizePreflight(agentNotes: String, prompt: String, mode: AgentExecutionMode) async throws -> AgentNotesPreflightSummary {
        let session = LanguageModelSession(
            instructions: Instructions {
                "Summarize AgentNotes only for the current prompt."
                "Prefer active claims, conflicts, blockers, and exact next claim."
                "Do not invent commits, tests, or file state."
            }
        )
        let response = try await session.respond(generating: GeneratedAgentNotesPreflightSummary.self) {
            Prompt("""
            Mode: \(mode.label)
            User prompt:
            \(prompt)

            AgentNotes content:
            \(Self.truncate(agentNotes, limit: 24_000))
            """)
        }
        let generated = response.content
        return AgentNotesPreflightSummary(
            relevantActiveClaims: generated.relevantActiveClaims,
            blockingConflicts: generated.blockingConflicts,
            suggestedClaim: generated.suggestedClaim,
            promptInjectionText: generated.promptInjectionText
        )
    }

    func proposeMerge(localContent: String, generatedContent: String) async throws -> AgentNotesMergeProposal {
        let session = LanguageModelSession(
            instructions: Instructions {
                "Merge AgentNotes content losslessly."
                "Preserve chronological facts, validation evidence, blockers, and conflict markers."
                "List unresolved conflicts instead of guessing."
            }
        )
        let response = try await session.respond(generating: GeneratedAgentNotesMergeProposal.self) {
            Prompt("""
            Local AgentNotes:
            \(Self.truncate(localContent, limit: 24_000))

            Generated AgentNotes:
            \(Self.truncate(generatedContent, limit: 24_000))
            """)
        }
        let generated = response.content
        return AgentNotesMergeProposal(
            mergedContent: generated.mergedContent,
            retainedLocalLines: generated.retainedLocalLines,
            retainedGeneratedLines: generated.retainedGeneratedLines,
            unresolvedConflicts: generated.unresolvedConflicts,
            explanation: generated.explanation
        )
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return "[truncated to last \(limit) chars]\n" + String(text.suffix(limit))
    }
}
#endif
```

- [ ] **Step 3: Add factory**

```swift
enum AgentNotesIntelligenceFactory {
    static func makeDefault(
        availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker()
    ) -> any AgentNotesIntelligencing {
        let availability = availabilityChecker.currentAvailability()
        guard availability.isAvailable else {
            return NoopAgentNotesIntelligence(reason: availability.message)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return LiveFoundationModelsAgentNotesIntelligence()
        }
        return NoopAgentNotesIntelligence(reason: FoundationModelsAvailability.frameworkUnavailable.message)
        #else
        return NoopAgentNotesIntelligence(reason: FoundationModelsAvailability.frameworkUnavailable.message)
        #endif
    }
}
```

### Task 8: Wire Intelligent Preflight Into Dispatch

**Files:**
- Modify: `Agenic Load-Balancer/Services/CoordinationAndSync.swift`
- Modify: `Agenic Load-Balancer/Services/RunDispatcher.swift`
- Test: extend `Agenic Load-BalancerTests/CoordinationCheckpointTests.swift`

- [ ] **Step 1: Add full AgentNotes read**

In `ProjectCoordinationActor`, add:

```swift
func readAgentNotes(rootPath: String) -> String? {
    let fileURL = agentNotesURL(rootPath: rootPath)
    guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
    return try? coordinatedReadString(at: fileURL)
}
```

- [ ] **Step 2: Extend `RunDispatcher.dispatch`**

Change the signature:

```swift
func dispatch(
    plan: RunPlan,
    agentNotesExcerpt: String? = nil,
    agentNotesPreflightSummary: AgentNotesPreflightSummary? = nil,
    modelContext: ModelContext
)
```

Change prompt composition call:

```swift
let promptForCommand = Self.composeCommandPrompt(
    userPrompt: plan.prompt,
    agentNotesExcerpt: agentNotesPreflightSummary?.promptInjectionText ?? agentNotesExcerpt
)
```

- [ ] **Step 3: Add preflight summary test**

```swift
@Test func composeCommandPromptPrefersIntelligentSummaryText() {
    let prompt = RunDispatcher.composeCommandPrompt(
        userPrompt: "Fix failing tests",
        agentNotesExcerpt: "Relevant active claim: Phase 7.2 validation pending"
    )

    #expect(prompt.contains("Active AgentNotes excerpt"))
    #expect(prompt.contains("Phase 7.2 validation pending"))
    #expect(prompt.contains("Fix failing tests"))
}
```

### Task 9: Wire AI-Assisted Reconciliation UI

**Files:**
- Create: `Agenic Load-Balancer/Views/AgentNotesReconciliationView.swift` or modify existing AgentNotes section in `ContentView.swift`
- Test: UI smoke through existing UI tests if the project already has launch tests

- [ ] **Step 1: Add merge proposal panel**

```swift
struct AgentNotesMergeProposalView: View {
    let proposal: AgentNotesMergeProposal
    let apply: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI-assisted merge proposal", systemImage: "sparkles")
                .font(.headline)
            Text(proposal.explanation)
            if !proposal.unresolvedConflicts.isEmpty {
                ForEach(proposal.unresolvedConflicts, id: \.self) { conflict in
                    Label(conflict, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            ScrollView {
                Text(proposal.mergedContent)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Cancel", action: cancel)
                Spacer()
                Button("Apply Merge", systemImage: "checkmark.circle", action: apply)
                    .disabled(!proposal.unresolvedConflicts.isEmpty)
            }
        }
        .padding(16)
    }
}
```

- [ ] **Step 2: Keep final write gated**

The `Apply Merge` action must call `ProjectCoordinationActor.applyReconciliation(rootPath:suggestedContent:)` only after a `confirmationDialog` that includes:

```text
This replaces AgentNotes.md with the reviewed merge proposal. A snapshot or Git checkpoint should exist before applying this to important project roots.
```

- [ ] **Step 3: Run full tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test
```

Expected:

```text
** TEST SUCCEEDED **
```

## Phase 7.5: Foundation Models Routing Tie-Breaker

### Task 10: Add Tie-Break Value Types And Protocol

**Files:**
- Create: `Agenic Load-Balancer/Services/RoutingTieBreaker.swift`
- Test: `Agenic Load-BalancerTests/RoutingTieBreakerTests.swift`

- [ ] **Step 1: Add value types**

```swift
import Foundation

struct RoutingTieBreak: Sendable, Codable, Hashable {
    var selectedProviderID: String
    var confidence: Double
    var reason: String
    var cautions: [String]
}

struct RoutingTieBreakInput: Sendable {
    var prompt: String
    var mode: AgentExecutionMode
    var candidates: [RoutingScoreBreakdown]
    var usage: [UsageSnapshot]
    var accuracy: [AccuracySnapshot]
    var coordinationEvents: [CoordinationEventSnapshot]
}

protocol RoutingTieBreaking: Sendable {
    func breakTie(input: RoutingTieBreakInput) async throws -> RoutingTieBreak
}
```

- [ ] **Step 2: Add noop and scripted implementations**

```swift
struct NoopRoutingTieBreaker: RoutingTieBreaking {
    let reason: String

    func breakTie(input: RoutingTieBreakInput) async throws -> RoutingTieBreak {
        guard let first = input.candidates.first else {
            throw RunSummaryError.unavailable(reason)
        }
        return RoutingTieBreak(
            selectedProviderID: first.providerID,
            confidence: 0,
            reason: reason,
            cautions: ["Deterministic score order preserved."]
        )
    }
}

struct ScriptedRoutingTieBreaker: RoutingTieBreaking {
    let result: RoutingTieBreak

    func breakTie(input: RoutingTieBreakInput) async throws -> RoutingTieBreak {
        result
    }
}
```

- [ ] **Step 3: Add tests**

```swift
@Suite("Phase 7.5 routing tie breaker")
struct RoutingTieBreakerTests {
    @Test func noopPreservesTopDeterministicCandidate() async throws {
        let candidate = RoutingScoreBreakdown(
            providerID: "openai.codex",
            providerName: "Codex",
            mode: .implementation,
            totalScore: 0.91,
            availabilityScore: 1,
            capabilityScore: 1,
            limitScore: 1,
            accuracyScore: 1,
            speedScore: 1,
            costScore: 1,
            rationale: "Top deterministic score",
            estimatedCostUSD: 0.01,
            limitImpact: "Low pressure",
            coordinationWarning: ""
        )
        let tieBreak = try await NoopRoutingTieBreaker(reason: "Unavailable").breakTie(
            input: RoutingTieBreakInput(
                prompt: "Implement feature",
                mode: .implementation,
                candidates: [candidate],
                usage: [],
                accuracy: [],
                coordinationEvents: []
            )
        )

        #expect(tieBreak.selectedProviderID == "openai.codex")
        #expect(tieBreak.cautions == ["Deterministic score order preserved."])
    }
}
```

### Task 11: Add Live Foundation Models Tie-Breaker

**Files:**
- Modify: `Agenic Load-Balancer/Services/RoutingTieBreaker.swift`

- [ ] **Step 1: Add generated shape**

```swift
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct GeneratedRoutingTieBreak: Sendable {
    @Guide(description: "Identifier of the best provider from the candidate list.")
    var selectedProviderID: String

    @Guide(description: "Confidence from 0.0 through 1.0.")
    var confidence: Double

    @Guide(description: "Short reason grounded in the candidate scores and prompt.")
    var reason: String

    @Guide(description: "Risks or caveats to show beside the recommendation.")
    var cautions: [String]
}
#endif
```

- [ ] **Step 2: Add live implementation**

```swift
#if canImport(FoundationModels)
@available(macOS 26.0, *)
struct LiveFoundationModelsRoutingTieBreaker: RoutingTieBreaking {
    func breakTie(input: RoutingTieBreakInput) async throws -> RoutingTieBreak {
        let candidateText = input.candidates.map { candidate in
            "\(candidate.providerID) | \(candidate.providerName) | score \(candidate.totalScore) | \(candidate.rationale)"
        }.joined(separator: "\n")
        let session = LanguageModelSession(
            instructions: Instructions {
                "Choose one provider only from the candidate IDs."
                "Use deterministic scores as the source of truth."
                "Prefer the provider best fit for the prompt when scores are close."
            }
        )
        let response = try await session.respond(generating: GeneratedRoutingTieBreak.self) {
            Prompt("""
            Mode: \(input.mode.label)
            Prompt: \(input.prompt)
            Close-score candidates:
            \(candidateText)
            """)
        }
        let generated = response.content
        return RoutingTieBreak(
            selectedProviderID: generated.selectedProviderID,
            confidence: max(0, min(generated.confidence, 1)),
            reason: generated.reason,
            cautions: generated.cautions
        )
    }
}
#endif
```

- [ ] **Step 3: Add factory**

```swift
enum RoutingTieBreakerFactory {
    static func makeDefault(
        availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker()
    ) -> any RoutingTieBreaking {
        let availability = availabilityChecker.currentAvailability()
        guard availability.isAvailable else {
            return NoopRoutingTieBreaker(reason: availability.message)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return LiveFoundationModelsRoutingTieBreaker()
        }
        return NoopRoutingTieBreaker(reason: FoundationModelsAvailability.frameworkUnavailable.message)
        #else
        return NoopRoutingTieBreaker(reason: FoundationModelsAvailability.frameworkUnavailable.message)
        #endif
    }
}
```

### Task 12: Integrate Close-Score Tie-Breaking

**Files:**
- Modify: `Agenic Load-Balancer/Services/RoutingEngine.swift`
- Modify: `Agenic Load-Balancer/ContentView.swift`
- Test: extend `Agenic Load-BalancerTests/RoutingTieBreakerTests.swift`

- [ ] **Step 1: Add recommendation wrapper**

```swift
struct RoutingRecommendation: Sendable, Hashable {
    var ranked: [RoutingScoreBreakdown]
    var tieBreak: RoutingTieBreak?

    var selected: RoutingScoreBreakdown? {
        guard let tieBreak else { return ranked.first }
        return ranked.first { $0.providerID == tieBreak.selectedProviderID } ?? ranked.first
    }
}
```

- [ ] **Step 2: Add close-score detector**

```swift
extension RoutingEngine {
    nonisolated static func closeScoreCandidates(
        from ranked: [RoutingScoreBreakdown],
        threshold: Double = 0.035,
        limit: Int = 3
    ) -> [RoutingScoreBreakdown] {
        guard let top = ranked.first else { return [] }
        return Array(ranked.prefix(limit).filter { abs(top.totalScore - $0.totalScore) <= threshold })
    }
}
```

- [ ] **Step 3: Add coordinator method without changing deterministic `rank`**

Create a small coordinator in `RoutingTieBreaker.swift`:

```swift
actor RoutingRecommendationCoordinator {
    private let routingEngine: RoutingEngine
    private let tieBreaker: any RoutingTieBreaking

    init(
        routingEngine: RoutingEngine = AppServices.routingEngine,
        tieBreaker: any RoutingTieBreaking = RoutingTieBreakerFactory.makeDefault()
    ) {
        self.routingEngine = routingEngine
        self.tieBreaker = tieBreaker
    }

    func recommend(
        prompt: String,
        mode: AgentExecutionMode,
        providers: [AgentProviderSnapshot],
        usage: [UsageSnapshot],
        accuracy: [AccuracySnapshot],
        coordinationEvents: [CoordinationEventSnapshot]
    ) async -> RoutingRecommendation {
        let ranked = await routingEngine.rank(
            prompt: prompt,
            mode: mode,
            providers: providers,
            usage: usage,
            accuracy: accuracy,
            coordinationEvents: coordinationEvents
        )
        let candidates = RoutingEngine.closeScoreCandidates(from: ranked)
        guard candidates.count > 1 else {
            return RoutingRecommendation(ranked: ranked, tieBreak: nil)
        }
        let input = RoutingTieBreakInput(
            prompt: prompt,
            mode: mode,
            candidates: candidates,
            usage: usage,
            accuracy: accuracy,
            coordinationEvents: coordinationEvents
        )
        let tieBreak = try? await tieBreaker.breakTie(input: input)
        return RoutingRecommendation(ranked: ranked, tieBreak: tieBreak)
    }
}
```

- [ ] **Step 4: UI display rule**

In route score UI, add:

```swift
if let tieBreak = recommendation.tieBreak, score.providerID == tieBreak.selectedProviderID {
    Label("On-device tie-break: \(tieBreak.reason)", systemImage: "sparkles")
        .foregroundStyle(.accent)
}
```

Keep all original score bars visible so users can see the model did not replace deterministic scoring.

- [ ] **Step 5: Run full tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test
```

Expected:

```text
** TEST SUCCEEDED **
```

## Phase 7.6: Autonomous Multi-Agent Project Development Manager

### Task 13: Define Autonomy Levels And Policy

**Files:**
- Create: `Agenic Load-Balancer/Services/AutonomyPolicy.swift`
- Test: `Agenic Load-BalancerTests/AutonomyPolicyTests.swift`

- [ ] **Step 1: Add policy values**

```swift
import Foundation

enum AutonomyLevel: String, CaseIterable, Identifiable, Sendable, Codable, Hashable {
    case observeOnly
    case planOnly
    case proposeActions
    case executeApprovedSteps
    case trustedWorkspaceAutopilot

    var id: String { rawValue }
}

struct AutonomyPolicy: Sendable, Codable, Hashable {
    var level: AutonomyLevel
    var allowedRootPaths: [String]
    var protectedPathPatterns: [String]
    var requiresApprovalForShell: Bool
    var requiresApprovalForWrites: Bool
    var requiresApprovalForCommitPush: Bool
    var maxConcurrentRuns: Int
    var maxEstimatedCostUSD: Double

    static let defaultSafe = AutonomyPolicy(
        level: .proposeActions,
        allowedRootPaths: [],
        protectedPathPatterns: [".git", ".env", "Secrets", "Keychain", "DerivedData"],
        requiresApprovalForShell: true,
        requiresApprovalForWrites: true,
        requiresApprovalForCommitPush: true,
        maxConcurrentRuns: 2,
        maxEstimatedCostUSD: 1.00
    )
}

enum AutonomyPolicyDecision: Sendable, Equatable {
    case allowed
    case requiresApproval(String)
    case denied(String)
}
```

- [ ] **Step 2: Add evaluator**

```swift
struct AutonomyPolicyEvaluator: Sendable {
    func evaluateWrite(path: String, policy: AutonomyPolicy) -> AutonomyPolicyDecision {
        guard policy.allowedRootPaths.contains(where: { path.hasPrefix($0) }) else {
            return .denied("Path is outside allowed project roots.")
        }
        if policy.protectedPathPatterns.contains(where: { path.contains($0) }) {
            return .requiresApproval("Path matches protected pattern.")
        }
        return policy.requiresApprovalForWrites ? .requiresApproval("Writes require approval.") : .allowed
    }

    func evaluateRun(mode: AgentExecutionMode, estimatedCostUSD: Double, policy: AutonomyPolicy) -> AutonomyPolicyDecision {
        guard estimatedCostUSD <= policy.maxEstimatedCostUSD else {
            return .denied("Estimated cost exceeds policy budget.")
        }
        if mode == .commitPushCheckpoint && policy.requiresApprovalForCommitPush {
            return .requiresApproval("Commit and push require approval.")
        }
        if policy.requiresApprovalForShell && mode != .recommendOnly && mode != .planOnly {
            return .requiresApproval("Shell-backed execution requires approval.")
        }
        return .allowed
    }
}
```

- [ ] **Step 3: Add tests**

```swift
@Suite("Phase 7.6 autonomy policy")
struct AutonomyPolicyTests {
    @Test func deniesWritesOutsideAllowedRoot() {
        let policy = AutonomyPolicy.defaultSafe
        let decision = AutonomyPolicyEvaluator().evaluateWrite(path: "/tmp/file.swift", policy: policy)
        #expect(decision == .denied("Path is outside allowed project roots."))
    }

    @Test func commitPushRequiresApprovalByDefault() {
        var policy = AutonomyPolicy.defaultSafe
        policy.allowedRootPaths = ["/repo"]
        let decision = AutonomyPolicyEvaluator().evaluateRun(
            mode: .commitPushCheckpoint,
            estimatedCostUSD: 0.01,
            policy: policy
        )
        #expect(decision == .requiresApproval("Commit and push require approval."))
    }
}
```

### Task 14: Add CloudKit-Compatible Autonomy Models

**Files:**
- Modify: `Agenic Load-Balancer/Models/AgenicModels.swift`
- Test: `Agenic Load-BalancerTests/AutonomyPolicyTests.swift`

- [ ] **Step 1: Add model registrations**

Append these to `AgenicDataModel.models`:

```swift
AutonomyGoalRecord.self,
AutonomyPlanRecord.self,
AutonomyTaskRecord.self,
AutonomyPolicyRecord.self,
MachinePeerRecord.self,
AutonomyOperationRecord.self,
ConflictResolutionRecord.self,
ValidationGateRecord.self,
AuditTrailRecord.self,
```

- [ ] **Step 2: Add records with optional relationships and scalar fields**

```swift
@Model
final class AutonomyGoalRecord {
    var identifier: String = ""
    var projectID: String?
    var title: String = ""
    var goalDescription: String = ""
    var status: String = "planned"
    var autonomyLevel: String = AutonomyLevel.proposeActions.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(identifier: String = UUID().uuidString, projectID: String? = nil, title: String, goalDescription: String) {
        self.identifier = identifier
        self.projectID = projectID
        self.title = title
        self.goalDescription = goalDescription
    }
}

@Model
final class AutonomyTaskRecord {
    var identifier: String = ""
    var goalID: String?
    var parentTaskID: String?
    var title: String = ""
    var detail: String = ""
    var status: String = CoordinationStatus.planned.rawValue
    var assignedProviderID: String?
    var dependencyIDsJSON: String = "[]"
    var validationCommand: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(identifier: String = UUID().uuidString, goalID: String? = nil, title: String, detail: String) {
        self.identifier = identifier
        self.goalID = goalID
        self.title = title
        self.detail = detail
    }
}
```

Add the same CloudKit-compatible shape for:

```swift
@Model final class AutonomyPlanRecord { var identifier = ""; var goalID: String?; var summary = ""; var taskIDsJSON = "[]"; var createdAt = Date(); var updatedAt = Date() }
@Model final class AutonomyPolicyRecord { var identifier = ""; var projectID: String?; var policyJSON = "{}"; var createdAt = Date(); var updatedAt = Date() }
@Model final class MachinePeerRecord { var identifier = ""; var displayName = ""; var deviceFingerprintHash = ""; var lastSeenAt: Date?; var syncStatus = "unknown"; var createdAt = Date(); var updatedAt = Date() }
@Model final class AutonomyOperationRecord { var identifier = ""; var entityID = ""; var entityType = ""; var operationKind = ""; var lamportClock: Int = 0; var machineID = ""; var payloadJSON = "{}"; var createdAt = Date() }
@Model final class ConflictResolutionRecord { var identifier = ""; var entityID = ""; var conflictKind = ""; var status = "open"; var localPayloadJSON = "{}"; var remotePayloadJSON = "{}"; var resolutionJSON = "{}"; var createdAt = Date(); var resolvedAt: Date? }
@Model final class ValidationGateRecord { var identifier = ""; var taskID: String?; var command = ""; var status = "notRun"; var outputExcerpt = ""; var startedAt: Date?; var endedAt: Date? }
@Model final class AuditTrailRecord { var identifier = ""; var goalID: String?; var taskID: String?; var eventKind = ""; var detail = ""; var createdAt = Date() }
```

When writing the actual code, use full initializers like the existing model style, not compact memberwise sketches. Keep arrays encoded as JSON strings unless the app already has a CloudKit-safe transform pattern for arrays.

- [ ] **Step 3: Add schema registration test**

```swift
@Test func autonomyModelsAreRegisteredInSchema() {
    let names = AgenicDataModel.models.map { String(describing: $0) }
    #expect(names.contains("AutonomyGoalRecord"))
    #expect(names.contains("AutonomyTaskRecord"))
    #expect(names.contains("ConflictResolutionRecord"))
}
```

### Task 15: Add ConflictResolutionEngine

**Files:**
- Create: `Agenic Load-Balancer/Services/ConflictResolutionEngine.swift`
- Test: `Agenic Load-BalancerTests/ConflictResolutionEngineTests.swift`

- [ ] **Step 1: Add deterministic merge values**

```swift
import Foundation

struct OperationEnvelope: Sendable, Codable, Hashable {
    var identifier: String
    var entityID: String
    var entityType: String
    var operationKind: String
    var lamportClock: Int
    var machineID: String
    var payload: [String: String]
}

enum ConflictResolutionOutcome: Sendable, Equatable {
    case merged(payload: [String: String], explanation: String)
    case requiresReview(reason: String)
}

struct ConflictResolutionEngine: Sendable {
    func resolve(local: OperationEnvelope, remote: OperationEnvelope) -> ConflictResolutionOutcome {
        guard local.entityID == remote.entityID, local.entityType == remote.entityType else {
            return .requiresReview(reason: "Operations target different entities.")
        }
        if local.operationKind == "appendAudit" && remote.operationKind == "appendAudit" {
            let merged = local.payload.merging(remote.payload) { left, right in
                [left, right].sorted().joined(separator: "\n")
            }
            return .merged(payload: merged, explanation: "Audit appends are commutative and both entries were retained.")
        }
        if local.lamportClock == remote.lamportClock && local.payload != remote.payload {
            return .requiresReview(reason: "Concurrent non-commutative edits require review.")
        }
        return local.lamportClock > remote.lamportClock
            ? .merged(payload: local.payload, explanation: "Local operation has the newer Lamport clock.")
            : .merged(payload: remote.payload, explanation: "Remote operation has the newer Lamport clock.")
    }
}
```

- [ ] **Step 2: Add tests**

```swift
@Suite("Phase 7.6 conflict resolution")
struct ConflictResolutionEngineTests {
    @Test func concurrentDifferentPayloadRequiresReview() {
        let local = OperationEnvelope(identifier: "l", entityID: "task-1", entityType: "task", operationKind: "setStatus", lamportClock: 4, machineID: "mac-a", payload: ["status": "running"])
        let remote = OperationEnvelope(identifier: "r", entityID: "task-1", entityType: "task", operationKind: "setStatus", lamportClock: 4, machineID: "mac-b", payload: ["status": "blocked"])

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)
        #expect(outcome == .requiresReview(reason: "Concurrent non-commutative edits require review."))
    }

    @Test func auditAppendsRetainBothPayloads() {
        let local = OperationEnvelope(identifier: "l", entityID: "goal-1", entityType: "audit", operationKind: "appendAudit", lamportClock: 1, machineID: "mac-a", payload: ["line": "local"])
        let remote = OperationEnvelope(identifier: "r", entityID: "goal-1", entityType: "audit", operationKind: "appendAudit", lamportClock: 1, machineID: "mac-b", payload: ["line": "remote"])

        let outcome = ConflictResolutionEngine().resolve(local: local, remote: remote)
        #expect(outcome == .merged(payload: ["line": "local\nremote"], explanation: "Audit appends are commutative and both entries were retained."))
    }
}
```

### Task 16: Add AutonomousProjectManager

**Files:**
- Create: `Agenic Load-Balancer/Services/AutonomousProjectManager.swift`
- Test: `Agenic Load-BalancerTests/AutonomousProjectManagerTests.swift`

- [ ] **Step 1: Add goal-to-plan values**

```swift
import Foundation
import SwiftData

struct AutonomousGoalRequest: Sendable {
    var title: String
    var goalDescription: String
    var projectID: String?
    var projectRootPath: String?
    var autonomyPolicy: AutonomyPolicy
}

struct AutonomousTaskDraft: Sendable, Hashable {
    var title: String
    var detail: String
    var mode: AgentExecutionMode
    var dependencyTitles: [String]
    var validationCommand: String?
}

struct AutonomousPlanDraft: Sendable, Hashable {
    var summary: String
    var tasks: [AutonomousTaskDraft]
}
```

- [ ] **Step 2: Add planner protocol and deterministic starter planner**

```swift
protocol GoalPlanning: Sendable {
    func plan(request: AutonomousGoalRequest) async throws -> AutonomousPlanDraft
}

struct DeterministicGoalPlanner: GoalPlanning {
    func plan(request: AutonomousGoalRequest) async throws -> AutonomousPlanDraft {
        AutonomousPlanDraft(
            summary: "Plan for \(request.title)",
            tasks: [
                AutonomousTaskDraft(
                    title: "Inspect repo contract",
                    detail: "Read AgentNotes.md, PLAN.md, AgentPlan.md, README, project files, and git status before editing.",
                    mode: .readReview,
                    dependencyTitles: [],
                    validationCommand: nil
                ),
                AutonomousTaskDraft(
                    title: "Create implementation plan",
                    detail: "Break the goal into scoped tasks with file ownership and validation gates.",
                    mode: .planOnly,
                    dependencyTitles: ["Inspect repo contract"],
                    validationCommand: nil
                ),
                AutonomousTaskDraft(
                    title: "Execute approved implementation",
                    detail: "Dispatch the best provider for the approved task, stream logs, and record outcomes.",
                    mode: .implementation,
                    dependencyTitles: ["Create implementation plan"],
                    validationCommand: request.projectRootPath.map { _ in "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project \"Agenic Load-Balancer.xcodeproj\" -scheme \"Agenic Load-Balancer\" -destination \"platform=macOS\" CODE_SIGNING_ALLOWED=NO test" }
                )
            ]
        )
    }
}
```

- [ ] **Step 3: Add manager actor**

```swift
actor AutonomousProjectManager {
    private let planner: any GoalPlanning
    private let policyEvaluator: AutonomyPolicyEvaluator

    init(
        planner: any GoalPlanning = DeterministicGoalPlanner(),
        policyEvaluator: AutonomyPolicyEvaluator = AutonomyPolicyEvaluator()
    ) {
        self.planner = planner
        self.policyEvaluator = policyEvaluator
    }

    func draftPlan(request: AutonomousGoalRequest) async throws -> AutonomousPlanDraft {
        try await planner.plan(request: request)
    }

    func evaluate(task: AutonomousTaskDraft, request: AutonomousGoalRequest, estimatedCostUSD: Double) -> AutonomyPolicyDecision {
        policyEvaluator.evaluateRun(
            mode: task.mode,
            estimatedCostUSD: estimatedCostUSD,
            policy: request.autonomyPolicy
        )
    }
}
```

- [ ] **Step 4: Add tests**

```swift
@Suite("Phase 7.6 autonomous project manager")
struct AutonomousProjectManagerTests {
    @Test func deterministicPlannerCreatesInspectionFirst() async throws {
        let request = AutonomousGoalRequest(
            title: "Ship command bar",
            goalDescription: "Build Phase 7.3",
            projectID: "project-1",
            projectRootPath: "/repo",
            autonomyPolicy: .defaultSafe
        )
        let draft = try await AutonomousProjectManager().draftPlan(request: request)
        #expect(draft.tasks.first?.title == "Inspect repo contract")
    }

    @Test func managerRequiresApprovalForImplementationUnderDefaultPolicy() async throws {
        let request = AutonomousGoalRequest(
            title: "Ship command bar",
            goalDescription: "Build Phase 7.3",
            projectID: "project-1",
            projectRootPath: "/repo",
            autonomyPolicy: .defaultSafe
        )
        let task = AutonomousTaskDraft(title: "Execute", detail: "Edit files", mode: .implementation, dependencyTitles: [], validationCommand: nil)
        let decision = await AutonomousProjectManager().evaluate(task: task, request: request, estimatedCostUSD: 0.01)
        #expect(decision == .requiresApproval("Shell-backed execution requires approval."))
    }
}
```

### Task 17: Add ValidationGateRunner

**Files:**
- Create: `Agenic Load-Balancer/Services/ValidationGateRunner.swift`
- Test: `Agenic Load-BalancerTests/ValidationGateRunnerTests.swift`

- [ ] **Step 1: Add runner protocol**

```swift
import Foundation

struct ValidationGateResult: Sendable, Hashable {
    var command: String
    var exitCode: Int32
    var outputExcerpt: String
    var startedAt: Date
    var endedAt: Date

    var passed: Bool { exitCode == 0 }
}

protocol ValidationGateRunning: Sendable {
    func run(command: String, workingDirectory: String) async -> ValidationGateResult
}

struct ScriptedValidationGateRunner: ValidationGateRunning {
    let result: ValidationGateResult

    func run(command: String, workingDirectory: String) async -> ValidationGateResult {
        result
    }
}
```

- [ ] **Step 2: Add tests**

```swift
@Suite("Phase 7.6 validation gates")
struct ValidationGateRunnerTests {
    @Test func passedReflectsZeroExitCode() {
        let result = ValidationGateResult(
            command: "xcodebuild test",
            exitCode: 0,
            outputExcerpt: "** TEST SUCCEEDED **",
            startedAt: Date(),
            endedAt: Date()
        )
        #expect(result.passed)
    }
}
```

Add a real process-backed runner only after the policy and UI approval surfaces are in place. It must reuse the existing safe process-running patterns from `AgentProcessRunner` instead of creating a second shell implementation.

### Task 18: Add Machine Sync Coordinator

**Files:**
- Create: `Agenic Load-Balancer/Services/MachineSyncCoordinator.swift`
- Test: `Agenic Load-BalancerTests/MachineSyncCoordinatorTests.swift`

- [ ] **Step 1: Add sync health values**

```swift
import Foundation

enum MachineSyncStatus: String, Sendable, Codable, Hashable {
    case current
    case delayed
    case divergent
    case needsSnapshotVerification
}

struct MachineSyncHealth: Sendable, Codable, Hashable {
    var machineID: String
    var displayName: String
    var status: MachineSyncStatus
    var lastSeenAt: Date?
    var detail: String
}

struct MachineSyncCoordinator: Sendable {
    func classify(lastSeenAt: Date?, now: Date = Date()) -> MachineSyncStatus {
        guard let lastSeenAt else { return .needsSnapshotVerification }
        let age = now.timeIntervalSince(lastSeenAt)
        if age < 300 { return .current }
        if age < 3600 { return .delayed }
        return .needsSnapshotVerification
    }
}
```

- [ ] **Step 2: Add tests**

```swift
@Suite("Phase 7.6 machine sync")
struct MachineSyncCoordinatorTests {
    @Test func recentPeerIsCurrent() {
        let now = Date(timeIntervalSince1970: 1000)
        let status = MachineSyncCoordinator().classify(lastSeenAt: Date(timeIntervalSince1970: 900), now: now)
        #expect(status == .current)
    }

    @Test func missingPeerNeedsSnapshotVerification() {
        let status = MachineSyncCoordinator().classify(lastSeenAt: nil, now: Date())
        #expect(status == .needsSnapshotVerification)
    }
}
```

### Task 19: Add Autonomy Control Center UI

**Files:**
- Create: `Agenic Load-Balancer/Views/AutonomyControlCenterView.swift`
- Modify: `Agenic Load-Balancer/ContentView.swift`

- [ ] **Step 1: Add UI view**

```swift
import SwiftUI

struct AutonomyControlCenterView: View {
    @State private var goalTitle = ""
    @State private var goalDescription = ""
    @State private var level: AutonomyLevel = .proposeActions
    @State private var planSummary = ""

    let draftPlan: @Sendable (AutonomousGoalRequest) async throws -> AutonomousPlanDraft
    let projectID: String?
    let projectRootPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Autonomy")
                .font(.title2.bold())
            Picker("Level", selection: $level) {
                ForEach(AutonomyLevel.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            TextField("Goal", text: $goalTitle)
            TextEditor(text: $goalDescription)
                .frame(minHeight: 120)
            Button("Draft Plan", systemImage: "list.bullet.clipboard") {
                Task { await createDraft() }
            }
            ScrollView {
                Text(planSummary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
    }

    private func createDraft() async {
        var policy = AutonomyPolicy.defaultSafe
        policy.level = level
        if let projectRootPath {
            policy.allowedRootPaths = [projectRootPath]
        }
        let request = AutonomousGoalRequest(
            title: goalTitle,
            goalDescription: goalDescription,
            projectID: projectID,
            projectRootPath: projectRootPath,
            autonomyPolicy: policy
        )
        do {
            let draft = try await draftPlan(request)
            planSummary = ([draft.summary] + draft.tasks.map { "- \($0.title): \($0.detail)" }).joined(separator: "\n")
        } catch {
            planSummary = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Wire as a sidebar section**

Add a `ConsoleSection.autonomy` case, sidebar item with `cpu`, and switch branch:

```swift
case .autonomy:
    AutonomyControlCenterView(
        draftPlan: { request in
            try await AutonomousProjectManager().draftPlan(request: request)
        },
        projectID: selectedProject?.identifier,
        projectRootPath: selectedProject?.rootPath
    )
```

Use the existing selected project state names in `ContentView.swift`; do not duplicate project selection state.

## Final Validation And Handoff

### Task 20: Full Validation

**Files:**
- Inspect: all changed source and test files
- Modify: `AgentNotes.md`
- Modify: `PLAN.md`

- [ ] **Step 1: Run formatting/whitespace check**

```bash
git diff --check
```

Expected:

```text
no output
```

- [ ] **Step 2: Run full macOS test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Agenic Load-Balancer.xcodeproj" -scheme "Agenic Load-Balancer" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 3: Record durable handoff**

Add an `AgentNotes.md` entry:

```markdown
- [checkpointed] Phase 7.3-7.6 planning and implementation sequence
  Assignee: <agent name>
  Detail: Added AgentPlan.md with execution plan for natural-language command bar, intelligent AgentNotes preflight/reconciliation, Foundation Models routing tie-breaker, and autonomous multi-agent project management.
  Run: local planning/update turn on <date>
  Commit: <commit sha>
  Conflict: none
  Validation: `git diff --check` and full macOS xcodebuild test gate passed.
```

Update `PLAN.md` current handoff:

```markdown
- Current Phase 7 execution plan lives in `AgentPlan.md`.
- Next implementation pickup: Phase 7.3 Task 1, after confirming the canonical checkout and checkpointing Phase 7.2.
```

- [ ] **Step 4: Commit plan and implementation**

Use phase-sized commits:

```bash
git add AgentPlan.md AgentNotes.md PLAN.md
git commit -m "Plan Phase 7 autonomous command center"
```

For implementation commits, prefer:

```bash
git commit -m "Add natural-language command bar actions"
git commit -m "Add AgentNotes intelligence"
git commit -m "Add Foundation Models routing tie breaker"
git commit -m "Add autonomous project manager foundation"
```

## External Sources To Recheck Before Implementation

- Apple Foundation Models overview: https://developer.apple.com/documentation/FoundationModels
- Apple `LanguageModelSession`: https://developer.apple.com/documentation/foundationmodels/languagemodelsession
- Apple `Tool`: https://developer.apple.com/documentation/foundationmodels/tool
- Apple guide, generating content and performing tasks: https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models

## Self-Review Checklist

- [x] Phase 7.3 covers ranking agents, dispatch run drafts, provider probes, snapshots, AgentNotes reconciliation, and dashboard metric reads. Checkpointed in `30d3d9f`; focused command-bar tests and the full app unit-test bundle passed on May 20, 2026. Full-scheme validation is blocked by the UI-test runner timing out while enabling automation mode.
- [x] Phase 7.4 replaces raw byte-truncated preflight with relevance-focused summary and adds AI-assisted merge proposals without ungated writes. Checkpointed in `9df9c6c`; focused AgentNotes intelligence tests passed and `build-for-testing` succeeded on May 20, 2026. Broader test runs later stalled inside Xcode before the test host appeared.
- [x] Phase 7.5 keeps deterministic routing canonical and applies on-device tie-breaks only to close scores. Checkpointed in `1b8a55d`; `build-for-testing` succeeded on May 20, 2026. Focused test execution is still blocked by Xcode test orchestration stalling before a visible `xctest` child appears.
- [ ] Phase 7.6 defines autonomy as policy-governed goal planning, task dispatch, validation, checkpointing, cross-machine sync, and lossless conflict handling.
- [ ] Every Foundation Models call has availability gating and a fallback.
- [ ] Every mutating tool action requires explicit approval unless a future trusted policy explicitly permits it.
- [ ] Validation includes focused tests per phase plus full macOS `xcodebuild test`.
