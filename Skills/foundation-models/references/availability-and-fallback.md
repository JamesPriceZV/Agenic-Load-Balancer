# Availability state machine and Agenic-routing fallback design

`SystemLanguageModel.default.availability` is the gate every Foundation Models feature must pass through. This reference documents the complete state machine, the user-visible message for each branch, and how the Agenic Load-Balancer routing engine should fall back when on-device generation isn't viable.

## States

The `SystemLanguageModel.Availability` enum has two top-level cases:

- `.available` — the model is ready to generate.
- `.unavailable(_)` — wraps a reason. Apple may add reasons across SDK releases, so handle `@unknown default`.

Reasons observed in current SDKs:

| Reason | Meaning | User-facing message (suggested) |
| --- | --- | --- |
| `.appleIntelligenceNotEnabled` | User hasn't turned Apple Intelligence on in Settings → Apple Intelligence & Siri. | "This feature requires Apple Intelligence. Enable it in Settings → Apple Intelligence & Siri." |
| `.modelNotReady` | Model assets are still downloading or initialising. | "Apple Intelligence is preparing. Try again in a few minutes." |
| `.deviceNotSupported` | Hardware can't run the on-device model (older iPhones, older Macs). | "This feature isn't available on this device." |
| `.regionNotSupported` | Region restriction (varies by Apple region rollout). | "This feature isn't available in your region yet." |
| `@unknown default` | Future SDK reason. | "This feature is temporarily unavailable." |

## Branch template

Use this `switch` exactly. Don't combine cases — each one wants a different user message.

```swift
struct AIFeatureGate<Content: View, Fallback: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let fallback: (String) -> Fallback        // takes a reason string

    private let model = SystemLanguageModel.default

    var body: some View {
        switch model.availability {
        case .available:
            content()
        case .unavailable(.appleIntelligenceNotEnabled):
            fallback("Apple Intelligence isn't turned on.")
        case .unavailable(.modelNotReady):
            fallback("Apple Intelligence is preparing. Try again later.")
        case .unavailable(.deviceNotSupported):
            fallback("This device doesn't support on-device generation.")
        case .unavailable(.regionNotSupported):
            fallback("On-device generation isn't available in your region yet.")
        case .unavailable:
            fallback("On-device generation is temporarily unavailable.")
        @unknown default:
            fallback("On-device generation is temporarily unavailable.")
        }
    }
}
```

## Agenic Load-Balancer fallback policy

The Agenic Load-Balancer already orchestrates multiple agent providers (Codex, Claude Code, Copilot, Gemini, etc.) through a `RoutingEngine`. Treat the on-device foundation model as **one more provider** in that catalog and let the engine decide.

### Provider catalog entry

Add an `AgentProviderProfile` for the on-device model:

```swift
AgentProviderDraft(
    identifier: "apple-foundation-on-device",
    displayName: "Apple Foundation Models (on-device)",
    providerFamily: "apple",
    homepageURL: "https://developer.apple.com/documentation/foundationmodels",
    sourceURL: "system://foundation-models",
    binaryName: "(in-process)",                      // no CLI to launch
    installCommand: "(built into OS)",
    verificationCommand: "(checked via SystemLanguageModel.default.availability)",
    authGuide: "Enable Apple Intelligence in Settings.",
    authMethods: "system",
    capabilities: "structured-generation,streaming,tool-calling",
    supportedExecutionModes: "recommendOnly,readReview,planOnly",
    modelListSource: "system",
    costPolicySummary: "Free; runs on-device.",
    quotaPolicySummary: "Subject to Apple Intelligence availability.",
    safetyNotes: "Output is filtered by Apple's on-device guardrails."
)
```

Then in `AgentAdapters.swift`, route this provider through a new `FoundationModelsAdapter` instead of `GenericCLIAdapter` — the adapter calls `LanguageModelSession.streamResponse(...)` and converts each partial into the same `runner.stdoutLines` stream the rest of the dispatcher consumes. Tool calls map to existing actors (read AgentNotes, query SwiftData, etc.).

### Health-check integration

`ProviderHealthMonitor` should map availability states to its `ProviderAvailabilityState`:

| Foundation Models state | `ProviderAvailabilityState` |
| --- | --- |
| `.available` | `.available` |
| `.unavailable(.modelNotReady)` | `.error` (transient — retry) |
| `.unavailable(.appleIntelligenceNotEnabled)` | `.disabled` |
| `.unavailable(.deviceNotSupported)` / `.regionNotSupported` | `.missing` |

The dashboard heatmap then renders the same colour treatment as any other provider.

### Routing decision

When the `RoutingEngine` scores a turn:

- If `apple-foundation-on-device` is `.available` AND the user's prompt fits the on-device context window AND the request's mode is in the supported set, prefer it for `recommendOnly` / `readReview` / `planOnly` runs (latency + privacy + free).
- Fall through to CLI providers when the user requests `implementation` / `commitPushCheckpoint` modes (those need shell access the on-device model can't provide).
- If `.disabled` (Apple Intelligence off), surface a one-line tip in the routing breakdown: "Enable Apple Intelligence to make this provider available." — don't error.

### Approval-sheet UX

The existing Liquid Glass `ApprovalSheetView` already shows "Provider", "Estimated Cost", "Latency", and a route-score row. When the chosen provider is `apple-foundation-on-device`:

- Show "Cost: $0 (on-device)" in the cost row.
- Show "Latency: ~tokens/s on this device" with a measured per-run figure.
- Show a small "Apple Intelligence" badge with the `sparkles` SF Symbol.
- The "Run Command" preview should read: `streamResponse(generating: <Type>.self, …)` with the schema name — not a shell command.

### Rating and accuracy feedback

Hook on-device runs into the existing `AccuracyRating` / `RunOutcomeRecord` flow exactly the same as any other provider. The `PerformanceHistoryBuilder` will then learn whether on-device is preferable for specific modes/projects, and the routing engine's `successRate` and `averageLatencySeconds` signals will adapt accordingly.

## Bottom line

Don't write a separate "Apple Intelligence" surface. Plumb the on-device model into the routing engine as a peer provider, keep the same approval / outcome / dashboard flows, and let the existing accuracy + cost + latency machinery decide when it wins.
