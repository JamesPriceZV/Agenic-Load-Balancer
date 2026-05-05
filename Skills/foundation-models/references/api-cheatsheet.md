# Foundation Models API cheat sheet

Quick lookup of the framework's public surface, distilled from the `FoundationModelsTripPlanner` sample and Apple's developer documentation. Read this before writing code — you'll save round-trips through the docs.

## Module

```swift
import FoundationModels
```

Available on iOS 26+, iPadOS 26+, macOS 26+, visionOS 26+. Requires Apple Intelligence to be enabled by the user. No internet connection required for the default on-device model.

## Macros

### `@Generable`

Apply to a `struct` or `enum` to make it usable as a model output type. Generates:

- A JSON schema the model uses for guided generation.
- A type-safe decoder.
- A `T.PartiallyGenerated` companion type whose every field is `Optional` (use during streaming).
- Conformance to the framework's internal protocols.

Works with nested types (e.g. an `Itinerary` containing `[DayPlan]`) — the macro recurses.

```swift
@Generable struct Itinerary: Equatable { ... }
@Generable enum Kind { case foo, bar }
```

### `@Guide`

Apply to properties of a `@Generable` type to add per-field guidance. Multiple `@Guide`s on one property compose.

| Form | Purpose | Example |
| --- | --- | --- |
| `@Guide(description: "…")` | Plain-language hint about purpose | `@Guide(description: "An exciting name for the trip.")` |
| `@Guide(.anyOf([…]))` | Restrict to a fixed set of values | `@Guide(.anyOf(ModelData.landmarkNames))` |
| `@Guide(.count(N))` | Force exact array length | `@Guide(.count(3))` |
| `@Guide(.range(min...max))` | Numeric bounds | `@Guide(.range(1...7))` |

## Core types

### `SystemLanguageModel`

```swift
let model = SystemLanguageModel.default
switch model.availability {
case .available: …
case .unavailable(.appleIntelligenceNotEnabled): …
case .unavailable(.modelNotReady): …
case .unavailable(.deviceNotSupported): …
case .unavailable(.regionNotSupported): …
@unknown default: …
}
```

`SystemLanguageModel.default` is the on-device foundation model. Branch on `availability` before constructing a session.

### `LanguageModelSession`

```swift
let session = LanguageModelSession(
    tools: [findPointsOfInterestTool],
    instructions: Instructions { … }
)
```

Sessions hold:

- A list of tools the model may call.
- The system instructions (built via the `Instructions` result builder).
- Conversation state (so `streamResponse` calls accumulate context turn-over-turn).

Sessions are **not** Sendable — keep them on the actor (typically `@MainActor`) that constructed them.

#### `prewarm()`

Call ahead of the user's request to reduce first-token latency:

```swift
.task { planner = ItineraryPlanner(landmark: landmark); planner?.prewarm() }
```

#### `streamResponse(generating:includeSchemaInPrompt:options:_:)`

```swift
let stream = session.streamResponse(
    generating: Itinerary.self,
    includeSchemaInPrompt: false,
    options: GenerationOptions(sampling: .greedy)
) {
    "Generate a 3-day itinerary to \(landmark.name)."
    "Here is an example, but don't copy it:"
    Itinerary.exampleTripToJapan
}
for try await partial in stream {
    self.itinerary = partial.content
}
```

- `generating:` — the `@Generable` type the model will emit.
- `includeSchemaInPrompt:` — defaults `true` for ad-hoc types; pass `false` when `@Generable` already encoded the schema (the common case).
- `options:` — `GenerationOptions`. `.greedy` for reproducibility, `.random(top: k)` for variety.
- Trailing closure builds the **user prompt** with the same string-/value-stacking semantics as `Instructions { … }`.
- Iterating yields snapshots; `partial.content` is `T.PartiallyGenerated` — every field `Optional`.

#### `respond(to:options:)`

Non-streaming variant. Returns the fully-generated value once. Use only for short outputs that don't need progressive UI.

### `Instructions`

Result builder used both for system instructions and user prompts. Each statement contributes a chunk:

```swift
Instructions {
    "Your job is to create an itinerary."
    "Each day needs an activity, hotel and restaurant."
    """
    Always use the findPointsOfInterest tool …
    """
    FindPointsOfInterestTool.categories            // String value interpolated as text
    landmark.description
}
```

Anything that becomes a `String` is fair game — let-bound values, computed properties, and multi-line literals all stack in source order.

### `GenerationOptions`

```swift
GenerationOptions(sampling: .greedy)               // deterministic
GenerationOptions(sampling: .random(top: 4))       // diverse, top-k
```

Sampling strategies decide how the model picks tokens. Default is implementation-defined — set explicitly for reproducible UX.

### `Tool`

```swift
@Observable
final class FindPointsOfInterestTool: Tool {
    let name = "findPointsOfInterest"
    let description = "Finds points of interest for a landmark."

    @Generable
    struct Arguments {
        @Guide(description: "Type of destination to search for.")
        let pointOfInterest: Category
        @Guide(description: "Natural-language query.")
        let naturalLanguageQuery: String
    }

    func call(arguments: Arguments) async throws -> String { … }
}
```

- `name` — exact identifier the model will use to invoke the tool. Use lowerCamelCase.
- `description` — single sentence the model reads to decide *whether* to call.
- `Arguments` — `@Generable` so the model emits a typed payload.
- `call` — `async throws`, returns a plain `String` describing the result.

Register tools by passing them to `LanguageModelSession(tools: [...])` at construction.

## Partial-generation companion types

Every `@Generable` type `T` gets a sibling `T.PartiallyGenerated`:

- All fields become `Optional`.
- Identifiable / Equatable conformances carry through where the original conforms.
- Nested generables also expose their own `.PartiallyGenerated` form (e.g. `[DayPlan].PartiallyGenerated` is `[DayPlan.PartiallyGenerated]`).

Render partials with `if let` per field and animate via `Equatable`-driven `.animation(_:value:)`.

## Errors

`LanguageModelSession` throws Swift errors for:

- Generation failures (model couldn't produce valid output for the schema).
- Guard-rail violations (content the model refused to produce).
- Tool call failures (your tool's `call(arguments:)` threw).

Catch at the call site and surface via the UI — never silently swallow.

## When to use what

| Need | Use |
| --- | --- |
| One-shot structured output, output is fast | `respond(to:options:)` |
| Visible progressive output | `streamResponse(generating:…)` |
| Closed-set field | `@Generable enum` or `@Guide(.anyOf([...]))` |
| Exact-N array | `@Guide(.count(N))` |
| Numeric bounds | `@Guide(.range(min...max))` |
| Reproducible runs | `GenerationOptions(sampling: .greedy)` |
| Reduce first-token latency | `session.prewarm()` |
| Side-effecting lookups during generation | A `Tool` |
| Apple Intelligence off | Branch on `.unavailable(.appleIntelligenceNotEnabled)` |
