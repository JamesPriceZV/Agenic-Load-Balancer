---
name: foundation-models
description: Add intelligent app features with Apple's Foundation Models framework — guided generation with @Generable/@Guide, streaming partial output, tool calling, on-device system language model availability gating, and Liquid Glass UI patterns. Use this skill whenever the user asks for AI-powered features, on-device LLMs, structured output from a model, streaming generation in a SwiftUI view, Apple Intelligence integration, "tool use" inside their app, or anything that calls into FoundationModels / SystemLanguageModel / LanguageModelSession on iOS 26+, iPadOS 26+, macOS 26+, or visionOS 26+. Trigger this even if the user only says "AI feature", "smart suggestion", "summarize this with AI", "structured output", or names model APIs without saying "Foundation Models".
---

# Foundation Models — intelligent app features with on-device generative models

Apple's Foundation Models framework lets a Swift app drive an on-device LLM with type-safe, structured output. The model runs locally (subject to Apple Intelligence availability), so latency, privacy, and reliability characteristics are very different from a server LLM.

This skill captures the patterns Apple's `FoundationModelsTripPlanner` sample teaches, and adapts them for the Agenic Load-Balancer project's preferences: Swift 6 strict concurrency, Apple HIG, and Liquid Glass UI.

## When to reach for this skill

Pull this skill in whenever you're about to:

- Generate structured Swift values (an itinerary, a draft, a routing decision summary, a categorisation) from a natural-language prompt.
- Stream partial generation into a SwiftUI view that updates as tokens arrive.
- Let the model call **app-defined tools** (search, lookup, mutation) mid-generation.
- Show the right empty/disabled UI when **Apple Intelligence is off** or the model isn't ready.
- Decide between server LLM (which the Agenic Load-Balancer routes to via CLI providers) and on-device Foundation Models for a specific feature.

If the user is asking "should this be on-device?" or "do I need an internet connection?" — this skill is relevant.

## Mental model

Foundation Models has four building blocks. Keep them straight:

1. **`@Generable` types** — your output shape, declared as a plain Swift `struct` or `enum`. The macro generates a JSON schema, a type-safe decoder, and a `T.PartiallyGenerated` companion type whose fields are all `Optional`.
2. **`@Guide` annotations** — per-property natural-language instructions and constraints (`.anyOf`, `.count`, `.range`) that steer generation without bloating the prompt.
3. **`LanguageModelSession`** — the chat-shaped object you talk to. It owns instructions, registered tools, and conversation state. Sessions are cheap; build one per task or per feature surface.
4. **`Tool` protocol** — your own types the model can call. Each tool exposes `@Generable Arguments` and an async `call(arguments:)` that returns a `String` the model reads back as context.

Around those, you handle:

- **Availability gating** via `SystemLanguageModel.default.availability`.
- **Streaming** via `session.streamResponse(generating:...)` returning partials.
- **Determinism** via `GenerationOptions(sampling: .greedy)`.
- **Latency** via `session.prewarm()`.

## Standard implementation pattern

Follow this five-step recipe whenever you add a Foundation Models feature. The `FoundationModelsTripPlanner` sample uses this exact shape; copy it.

### Step 1 — Define the output shape with `@Generable` + `@Guide`

```swift
import FoundationModels

@Generable
struct Itinerary: Equatable {
    @Guide(description: "An exciting name for the trip.")
    let title: String

    @Guide(.anyOf(ModelData.landmarkNames))      // closed set
    let destinationName: String

    let description: String

    @Guide(description: "An explanation of how the itinerary meets the person's special requests.")
    let rationale: String

    @Guide(description: "A list of day-by-day plans.")
    @Guide(.count(3))                            // exact-N constraint
    let days: [DayPlan]
}

@Generable
enum Kind {                                      // closed-set categories — use enums, not strings
    case sightseeing
    case foodAndDining
    case shopping
    case hotelAndLodging
}
```

Rules of thumb:

- Use enums for categorical fields. The model can't invent an unknown case.
- Use `.anyOf(...)` when the legal set is data-driven (e.g. seeded from your repository).
- Use `.count(n)` to fix array length. Use `.range(_:to:)` for soft bounds.
- A short `@Guide(description:)` on a property is the single highest-leverage prompt-engineering knob — write the field's purpose in one sentence.
- Conform to `Equatable` so SwiftUI's `.animation(_:value:)` re-renders cleanly when partials change.

### Step 2 — Build the session with instructions and tools

```swift
@Observable
@MainActor
final class ItineraryPlanner {
    private(set) var itinerary: Itinerary.PartiallyGenerated?
    private(set) var pointOfInterestTool: FindPointsOfInterestTool
    private var session: LanguageModelSession
    var error: Error?
    let landmark: Landmark

    init(landmark: Landmark) {
        self.landmark = landmark
        let pointOfInterestTool = FindPointsOfInterestTool(landmark: landmark)
        self.session = LanguageModelSession(
            tools: [pointOfInterestTool],
            instructions: Instructions {
                "Your job is to create an itinerary for the person."
                "Each day needs an activity, hotel and restaurant."
                """
                Always use the findPointsOfInterest tool to find businesses \
                and activities in \(landmark.name), especially hotels \
                and restaurants.

                The point of interest categories may include:
                """
                FindPointsOfInterestTool.categories
                """
                Here is a description of \(landmark.name) for your reference:
                """
                landmark.description
            }
        )
        self.pointOfInterestTool = pointOfInterestTool
    }

    func prewarm() { session.prewarm() }
}
```

Notes:

- `Instructions { ... }` is a result builder — string literals, multi-line strings, and runtime-interpolated values all stack, in order, into the system prompt.
- The planner is `@Observable @MainActor` so SwiftUI binds directly without `@Published`/`ObservableObject`. Partial updates are MainActor-safe.
- `session` is private; expose only the data the view needs (the partial, the tool's lookup history, the error). This keeps Swift 6 sendability honest.
- Call `prewarm()` from `.task` on the screen *before* the user taps the generate button — first-token latency drops noticeably.

### Step 3 — Stream the response into a `PartiallyGenerated` value

```swift
func suggestItinerary(dayCount: Int) async throws {
    let stream = session.streamResponse(
        generating: Itinerary.self,
        includeSchemaInPrompt: false,            // schema embedded via macros
        options: GenerationOptions(sampling: .greedy)
    ) {
        "Generate a \(dayCount)-day itinerary to \(landmark.name)."
        "Give it a fun title and description."
        "Here is an example, but don't copy it:"
        Itinerary.exampleTripToJapan             // few-shot example
    }

    for try await partialResponse in stream {
        itinerary = partialResponse.content      // every iteration moves the UI
    }
}
```

Notes:

- `includeSchemaInPrompt: false` is the right default — the `@Generable` macro already injected the schema. Setting it to `true` re-emits the schema into the user prompt, which wastes tokens.
- `GenerationOptions(sampling: .greedy)` makes runs reproducible. Use `.random(top: k)` only when the user actively wants variety.
- Few-shot via a literal example value is more reliable than describing the format in prose. Pass the canonical shape, then tell the model "but don't copy it".
- Inside the `for try await` loop, just assign — SwiftUI animations driven by `.animation(.easeOut, value: itinerary)` will smoothly interpolate visible fields as `Optional`s flip from `nil` to populated.

### Step 4 — Render the partial in SwiftUI with Liquid Glass cards

```swift
struct ItineraryView: View {
    let itinerary: Itinerary.PartiallyGenerated

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title = itinerary.title {
                Text(title)
                    .contentTransition(.opacity)
                    .font(.largeTitle).fontWeight(.bold)
            }
            if let description = itinerary.description {
                Text(description).contentTransition(.opacity)
            }
            if let days = itinerary.days {
                ForEach(days) { plan in
                    DayCard(plan: plan).transition(.blurReplace)
                }
            }
        }
        .animation(.easeOut, value: itinerary)
    }
}
```

Liquid Glass / HIG patterns to copy from the sample:

- `.contentTransition(.opacity)` on each text field so growing strings fade rather than jank.
- `.transition(.blurReplace)` on items appearing inside a `ForEach` driven by partials.
- `.animation(.easeOut, value: itinerary)` on the container view, with the `@Generable` value `Equatable`.
- `.symbolEffect(.breathe, isActive: true)` plus an SF Symbol (`sparkles`, `wand.and.stars`) for the "AI is thinking" affordance — pair with a tool-call history list so users see the model is actively searching, not stalled.
- Wrap intermediate work in `.card()` (frosted-material rounded rectangle) to align with Liquid Glass.

### Step 5 — Define a tool the model can call

```swift
@Observable
final class FindPointsOfInterestTool: Tool {
    let name = "findPointsOfInterest"
    let description = "Finds points of interest for a landmark."

    let landmark: Landmark
    @MainActor var lookupHistory: [Lookup] = []   // observable for UI

    init(landmark: Landmark) { self.landmark = landmark }

    @Generable
    enum Category: String, CaseIterable {
        case campground, hotel, cafe, museum, marina, restaurant, nationalMonument
    }

    @Generable
    struct Arguments {
        @Guide(description: "This is the type of destination to look up for.")
        let pointOfInterest: Category

        @Guide(description: "The natural language query of what to search for.")
        let naturalLanguageQuery: String
    }

    @MainActor func recordLookup(arguments: Arguments) {
        lookupHistory.append(Lookup(history: arguments))
    }

    func call(arguments: Arguments) async throws -> String {
        await recordLookup(arguments: arguments)
        let results = mapItems(arguments: arguments)
        return "There are these \(arguments.pointOfInterest) in \(landmark.name): \(results.joined(separator: ", "))"
    }
}
```

Tool design rules:

- Tool name is `lowerCamelCase` — the model will see and call it by this exact name.
- Tool description is a *single sentence* — the model uses it to decide whether to call.
- `Arguments` is `@Generable` — so the model gets a typed schema, not a free-form payload.
- Return a **plain string** describing the result. The model reads it as context; don't return JSON unless your prompt also tells it the JSON shape.
- Side effects (network, MapKit, SwiftData writes) are fine inside `call`, but they must be Sendable-clean. Hop to `@MainActor` for UI state, like the lookup history list.
- Expose tool state (`lookupHistory`) so the view can render "Searching cafes…" badges while the model is mid-generation.

## Availability gating — the most-skipped step

Foundation Models is unavailable in several states. Branch on `SystemLanguageModel.default.availability` *before* you build a session, and design a graceful path for each branch:

```swift
struct TripPlanningView: View {
    let landmark: Landmark
    private let model = SystemLanguageModel.default

    var body: some View {
        switch model.availability {
        case .available:
            LandmarkTripView(landmark: landmark)
        case .unavailable(.appleIntelligenceNotEnabled):
            MessageView(landmark: landmark, message: """
                Trip Planner is unavailable because \
                Apple Intelligence hasn't been turned on.
                """)
        case .unavailable(.modelNotReady):
            MessageView(landmark: landmark, message: "Trip Planner isn't ready yet. Try again later.")
        default:
            // device unsupported, region restricted, etc.
            ScrollView { LandmarkDescriptionView(landmark: landmark) }
        }
    }
}
```

For Agenic Load-Balancer specifically: when an on-device feature is unavailable, fall back to dispatching the same prompt through the existing routing engine to a CLI provider — never crash, never grey-out without explanation. The same prompt-and-rating loop already exists; reuse it.

## Concurrency, errors, and Swift 6

- The planner / session owner should be `@Observable @MainActor` (not `ObservableObject`). Partials drive SwiftUI directly.
- `LanguageModelSession` is **not** Sendable across actors — keep it on the actor that constructed it.
- `Tool` types must be Sendable-safe. If they hold UI state, mark that state `@MainActor` and hop with `await`.
- Catch errors inside the view layer (`do { try await planner.suggestItinerary(...) } catch { planner.error = error }`) and render via a dedicated `MessageView` — `error.localizedDescription` is what the user sees. The model sometimes returns terms-of-service or content-safety errors; never swallow them silently.
- For testing, surround the call in a do/catch that records the error to a `@Test` expectation rather than letting it propagate — Foundation Models throws on guard-rail violations.

## Anti-patterns to avoid

- Using a free-form `String` field where an `enum` would do. The model will hallucinate values.
- Stuffing the entire schema into your prompt manually. Set `includeSchemaInPrompt: false` and let `@Generable` carry it.
- Awaiting the *full* response when streaming would visibly progress the UI. Always prefer `streamResponse` for anything user-facing.
- Calling tools that perform destructive writes without confirmation. Tools should be read-mostly; gate writes behind explicit user approval (mirror the Agenic Load-Balancer ApprovalSheet pattern).
- Skipping `prewarm()`. The first token after a cold session can be ~1s slower.
- Forgetting the availability switch. If Apple Intelligence is off, your screen looks broken.

## Project alignment — Agenic Load-Balancer specifics

This project's user preferences require Apple HIG, Liquid Glass, and Swift 6. When you add Foundation Models features here:

- Keep on-device generation as one **provider option** in the routing engine, not a hardcoded path. The dashboard already shows latency/success/cost per provider; on-device should appear there with cost = $0 and latency = measured locally.
- Persist `RunOutcomeRecord` for on-device runs the same way you do for CLI providers — same status, accuracy rating, commitSHA workflow. The accuracy feedback loop should treat Apple's on-device model like any other provider so the routing engine learns whether to prefer it.
- Tools should write through the existing actors (`SnapshotRestoreCoordinator`, `ProjectCoordinationActor`, etc.), never bypass them. SwiftData writes from a tool must hop to `@MainActor`.
- Match the existing Liquid Glass card / approval sheet idiom (see `ContentView.swift` `ApprovalSheetView`) for any new generation UI — frosted material, `.symbolEffect(.breathe)` while streaming, `Cancel` always present.

## Reference files

When you need more depth on a sub-topic, read the matching reference file in this skill folder:

- `references/api-cheatsheet.md` — one-page cheat sheet of every type, modifier, and option in the framework.
- `references/availability-and-fallback.md` — the full availability state machine and Agenic-routing fallback design.
- `examples/itinerary-planner.swift` — the reference `ItineraryPlanner` adapted to Agenic-style ownership.
- `examples/find-points-of-interest-tool.swift` — the reference `Tool` adapted for SwiftData-backed lookups.

## Apple documentation

When the user wants something the sample doesn't cover (multi-turn chat, function-calling beyond `Tool`, custom adapters, Writing Tools integration), open Apple's docs first — they ship updates faster than this skill:

- https://developer.apple.com/documentation/foundationmodels
- https://developer.apple.com/documentation/foundationmodels/adding-intelligent-app-features-with-generative-models
- https://developer.apple.com/documentation/foundationmodels/generable
- https://developer.apple.com/documentation/foundationmodels/languagemodelsession
- https://developer.apple.com/documentation/foundationmodels/tool

Always read the Apple docs **before** writing Foundation Models code — the API is still maturing and parameter shapes shift between betas.
