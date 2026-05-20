//
//  RunSummary.swift
//  Agenic Load-Balancer
//
//  Created by Claude on 5/6/26.
//
//  Phase 7.2: structured outcome classification using Apple's
//  FoundationModels guided generation. After a successful run, the live
//  console's stdout/stderr buffer is fed to a `LanguageModelSession` that
//  emits a `@Generable RunSummary` shape. The structured fields are then
//  stamped onto `RunOutcomeRecord` so the dashboard accuracy/performance
//  signals get measurably better data without regex-based parsing.
//
//  Design rules (matching the cross-cutting Phase 7 contract):
//  - The Sendable, Codable, Hashable `RunSummary` value type is the SHARED
//    surface used by the rest of the app (records, archive DTOs, UI). It
//    does NOT depend on the FoundationModels framework so the project still
//    type-checks on SDKs that don't ship it.
//  - The `@Generable` shape (`GeneratedRunSummary`) and the live summarizer
//    live behind `#if canImport(FoundationModels)` and
//    `@available(macOS 26.0, *)` gates so deployment to older SDKs remains
//    possible.
//  - Availability is checked via `FoundationModelsAvailabilityChecking`
//    before constructing a session — when Apple Intelligence is off the
//    factory returns `NoopRunSummarizer` and the dispatcher records a
//    user-facing reason instead of crashing.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Plain value types

/// Structured outcome classification for a completed run. Plain Sendable
/// value type so `RunOutcomeRecord`, `RunOutcomeDTO`, tests, and the UI
/// layer can all reason about a summary without importing FoundationModels.
struct RunSummary: Sendable, Codable, Hashable {
    /// Up to ~10 short paths the run touched, in display order.
    var filesChanged: [String]

    /// Number of tests that passed if the run was a test/build session, or
    /// `nil` when the run had no test suite.
    var testsPassed: Int?

    /// Number of tests that failed if the run was a test/build session, or
    /// `nil` when the run had no test suite.
    var testsFailed: Int?

    /// Single-sentence summary the dashboard surfaces alongside the run.
    var oneLineDescription: String

    /// The accuracy rating the model suggests based on the captured output.
    /// Always in `AccuracyRating.allCases`.
    var suggestedAccuracyRating: AccuracyRating

    init(
        filesChanged: [String] = [],
        testsPassed: Int? = nil,
        testsFailed: Int? = nil,
        oneLineDescription: String,
        suggestedAccuracyRating: AccuracyRating
    ) {
        self.filesChanged = filesChanged
        self.testsPassed = testsPassed
        self.testsFailed = testsFailed
        self.oneLineDescription = oneLineDescription
        self.suggestedAccuracyRating = suggestedAccuracyRating
    }
}

/// Inputs handed to the summarizer. Captures the prompt, mode, exit code,
/// and the captured stdout/stderr buffer so the model has full context.
struct RunSummaryInput: Sendable {
    let prompt: String
    let providerID: String
    let providerName: String
    let mode: AgentExecutionMode
    let exitCode: Int32?
    let durationSeconds: Double
    let standardOutput: String
    let standardError: String

    /// Hard cap on bytes fed into the prompt so a chatty CLI doesn't blow
    /// out the model's context window. Tail of the buffer is preferred so
    /// the most recent (typically most relevant) lines survive truncation.
    static let maxBufferBytes = 12_000

    /// Tail-truncated copy of the standard output buffer — the last
    /// `maxBufferBytes` characters, prefixed with a marker if anything was
    /// dropped. Used by live summarizers so they don't have to repeat the
    /// truncation logic.
    var truncatedStandardOutput: String {
        Self.truncate(standardOutput)
    }

    /// Tail-truncated copy of the standard error buffer. Same shape as
    /// `truncatedStandardOutput`.
    var truncatedStandardError: String {
        Self.truncate(standardError)
    }

    private static func truncate(_ buffer: String) -> String {
        guard buffer.count > maxBufferBytes else { return buffer }
        let suffix = String(buffer.suffix(maxBufferBytes))
        return "[truncated to last \(maxBufferBytes) chars]\n" + suffix
    }
}

/// Errors thrown by `RunSummarizing` implementations. Failures must NEVER
/// degrade the run outcome itself — the dispatcher is expected to catch
/// these and surface them as a separate non-blocking status.
enum RunSummaryError: Error, Sendable, LocalizedError, Equatable {
    case unavailable(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail):
            return "Run summary unavailable: \(detail)"
        case .generationFailed(let detail):
            return "Run summary generation failed: \(detail)"
        }
    }
}

/// Sendable indirection so the dispatcher / tests / live FoundationModels
/// path all share the same surface.
protocol RunSummarizing: Sendable {
    func summarize(input: RunSummaryInput) async throws -> RunSummary
}

// MARK: - Default & test helpers

/// Default summarizer used whenever Apple Intelligence is unavailable in
/// the current process (e.g. running on a host without the FoundationModels
/// framework, or with Apple Intelligence disabled). Always throws
/// `RunSummaryError.unavailable` so callers can surface a clear, localised
/// reason instead of falling back to silent regex.
struct NoopRunSummarizer: RunSummarizing {
    let reason: String

    init(reason: String = "Apple Foundation Models is not available on this device.") {
        self.reason = reason
    }

    func summarize(input _: RunSummaryInput) async throws -> RunSummary {
        throw RunSummaryError.unavailable(reason)
    }
}

/// Test-friendly summarizer driven by an injected closure. Lets tests
/// produce deterministic `RunSummary` values, simulate errors, and verify
/// the input that the dispatcher actually hands to the summarizer.
struct ScriptedRunSummarizer: RunSummarizing {
    /// Closure invoked for each `summarize(input:)` call.
    let handler: @Sendable (RunSummaryInput) async throws -> RunSummary

    init(handler: @escaping @Sendable (RunSummaryInput) async throws -> RunSummary) {
        self.handler = handler
    }

    /// Convenience initialiser that always returns `summary`.
    init(constant summary: RunSummary) {
        self.init { _ in summary }
    }

    /// Convenience initialiser that always throws `error`.
    init(throwing error: Error) {
        self.init { _ in throw error }
    }

    func summarize(input: RunSummaryInput) async throws -> RunSummary {
        try await handler(input)
    }
}

// MARK: - Factory

/// Picks the right summarizer at runtime. The dispatcher uses the default
/// implementation; tests override the dispatcher's `summarizer` parameter
/// so they never reach this code path.
enum RunSummarizerFactory {
    /// Build a summarizer suited to the current process. When Apple
    /// Foundation Models is `.available`, returns a live summarizer that
    /// calls `LanguageModelSession.respond(...)`. Otherwise returns a
    /// `NoopRunSummarizer` carrying the human-readable availability reason.
    static func makeDefault(
        availabilityChecker: any FoundationModelsAvailabilityChecking = SystemLanguageModelAvailabilityChecker()
    ) -> any RunSummarizing {
        let availability = availabilityChecker.currentAvailability()
        guard availability.isAvailable else {
            return NoopRunSummarizer(reason: availability.message)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return LiveFoundationModelsRunSummarizer()
        }
        return NoopRunSummarizer(reason: FoundationModelsAvailability.frameworkUnavailable.message)
        #else
        return NoopRunSummarizer(reason: FoundationModelsAvailability.frameworkUnavailable.message)
        #endif
    }
}

// MARK: - FoundationModels-backed implementation

#if canImport(FoundationModels)

/// Mirror of `AccuracyRating` exposed to the model as a closed-set enum.
/// Keeping this parallel keeps `AgenicModels.swift` framework-agnostic
/// while still letting the macro emit a closed-set schema instead of a
/// free-form string.
@available(macOS 26.0, *)
@Generable
enum GeneratedAccuracyRating: String, Sendable {
    case correct
    case minorFixNeeded
    case debugNeeded
    case recodeNeeded
    case brokeBuildOrTests
    case abandoned
    case userOverride
    case unrated

    /// Translate to the canonical `AccuracyRating` used elsewhere.
    var asAccuracyRating: AccuracyRating {
        switch self {
        case .correct: return .correct
        case .minorFixNeeded: return .minorFixNeeded
        case .debugNeeded: return .debugNeeded
        case .recodeNeeded: return .recodeNeeded
        case .brokeBuildOrTests: return .brokeBuildOrTests
        case .abandoned: return .abandoned
        case .userOverride: return .userOverride
        case .unrated: return .unrated
        }
    }
}

/// `@Generable` shape the on-device model emits. Each property carries a
/// short `@Guide` so the model has clear hints about what each field means
/// — the single most reliable prompt-engineering knob per Apple's guidance.
@available(macOS 26.0, *)
@Generable
struct GeneratedRunSummary: Sendable {
    @Guide(description: "Up to ten short relative paths the run modified or created. Empty when nothing changed.")
    var filesChanged: [String]

    @Guide(description: "Total tests that passed during the run. Use 0 when the run had no test suite.")
    var testsPassed: Int

    @Guide(description: "Total tests that failed during the run. Use 0 when the run had no test suite.")
    var testsFailed: Int

    @Guide(description: "Single-sentence summary describing what the agent accomplished, written in plain English.")
    var oneLineDescription: String

    @Guide(description: "Best-fit accuracy rating for this run, picked from the allowed enum cases.")
    var suggestedAccuracyRating: GeneratedAccuracyRating

    /// Translate to the framework-independent `RunSummary`. `testsPassed` /
    /// `testsFailed` round-trip as `nil` when the model emits `0` so the UI
    /// doesn't display "0 / 0" for runs with no test suite.
    func asRunSummary(includeTestCounts: Bool) -> RunSummary {
        RunSummary(
            filesChanged: filesChanged,
            testsPassed: includeTestCounts ? testsPassed : nil,
            testsFailed: includeTestCounts ? testsFailed : nil,
            oneLineDescription: oneLineDescription,
            suggestedAccuracyRating: suggestedAccuracyRating.asAccuracyRating
        )
    }
}

/// Live summarizer backed by `LanguageModelSession.respond(...)`. The
/// session is created per-call (not held across calls) so its non-Sendable
/// nature stays inside one isolation domain, matching the
/// `LiveFoundationModelsSessionDriver` pattern from Phase 7.1.
@available(macOS 26.0, *)
struct LiveFoundationModelsRunSummarizer: RunSummarizing {
    init() {}

    func summarize(input: RunSummaryInput) async throws -> RunSummary {
        let prompt = Self.composePrompt(for: input)
        do {
            let session = LanguageModelSession(
                instructions: Instructions {
                    "You classify the outcome of a coding-agent run."
                    "Read the user prompt, mode, exit code, and the captured standard output and standard error."
                    "Emit a typed RunSummary describing what the run accomplished, which files it touched, and the most accurate AccuracyRating from the allowed enum."
                    "If the run had no test suite, set testsPassed and testsFailed to 0. If you do not have evidence for a field, prefer minimal answers over speculation."
                }
            )
            // Matches the API shape used by Apple's
            // `FoundationModelsTripPlanner` sample (see
            // `LandmarkDescriptionView.swift:51`):
            //   session.streamResponse(to:generating:options:)
            // The non-streaming `respond(to:generating:options:)` is the
            // direct sibling — we don't need progressive UI for an outcome
            // classification.
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedRunSummary.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let includeTestCounts = input.mode == .testBuild
            return response.content.asRunSummary(includeTestCounts: includeTestCounts)
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw RunSummaryError.generationFailed(detail)
        }
    }

    /// Build the user prompt fed into `respond(to:)`. Fixed structure so the
    /// model always sees the same labelled sections; the captured stdout
    /// and stderr buffers are tail-truncated upstream by `RunSummaryInput`.
    static func composePrompt(for input: RunSummaryInput) -> String {
        let exit = input.exitCode.map(String.init) ?? "n/a"
        return """
        Provider: \(input.providerName) (\(input.providerID))
        Mode: \(input.mode.label)
        Duration (s): \(String(format: "%.2f", input.durationSeconds))
        Exit code: \(exit)

        --- Original user prompt ---
        \(input.prompt)

        --- Standard output (tail) ---
        \(input.truncatedStandardOutput)

        --- Standard error (tail) ---
        \(input.truncatedStandardError)
        """
    }
}

#endif

// MARK: - RunSummary serialisation helpers

extension RunSummary {
    /// JSON-encoded `filesChanged` array suitable for storage on a
    /// CloudKit-compatible `@Model` property (which only accepts primitive
    /// types). Empty array round-trips as `"[]"`.
    var filesChangedJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(filesChanged),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    /// Decode a `filesChanged` array from its JSON-string representation.
    /// Returns `[]` for malformed or empty input so call sites never crash.
    static func decodeFilesChanged(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
