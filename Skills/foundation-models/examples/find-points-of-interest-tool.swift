//
//  find-points-of-interest-tool.swift
//  Skills / foundation-models / examples
//
//  Reference implementation of the Tool protocol — a model-callable type that
//  accepts typed arguments and returns a string the model reads back as
//  context. The tool exposes its own observable state (`lookupHistory`) so the
//  SwiftUI view can show "Searching cafés…" badges while the model is mid-
//  generation.
//
//  Adapted from Apple's `FoundationModelsTripPlanner` sample.
//
//  This file is documentation — copy snippets into the project, do not add it
//  to the Xcode target as-is.

import FoundationModels
import SwiftUI

@Observable
final class FindPointsOfInterestTool: Tool {

    // MARK: Tool protocol surface

    /// Exact identifier the model will use to call this tool. Keep it
    /// lowerCamelCase and short enough to read in stack traces.
    let name = "findPointsOfInterest"

    /// Single sentence the model uses to decide whether to call this tool.
    /// Don't list categories or arguments here — those go on `Arguments`.
    let description = "Finds points of interest for a landmark."

    // MARK: Tool state

    let landmark: Landmark

    /// Observable list the SwiftUI view consumes while the model is running.
    /// MainActor-isolated because it drives UI; the framework hops onto it
    /// from `call` via `await`.
    @MainActor var lookupHistory: [Lookup] = []

    init(landmark: Landmark) {
        self.landmark = landmark
    }

    // MARK: Generable child types

    @Generable
    enum Category: String, CaseIterable {
        case campground
        case hotel
        case cafe
        case museum
        case marina
        case restaurant
        case nationalMonument
    }

    @Generable
    struct Arguments {
        @Guide(description: "This is the type of destination to look up for.")
        let pointOfInterest: Category

        @Guide(description: "The natural language query of what to search for.")
        let naturalLanguageQuery: String
    }

    // MARK: Tool entry point

    func call(arguments: Arguments) async throws -> String {
        // Hop to MainActor for the UI side-effect.
        await recordLookup(arguments: arguments)

        // In a real Agenic-style implementation this would dispatch through an
        // existing actor (SnapshotRestoreCoordinator, ProjectCoordinationActor,
        // a SwiftData read context, MapKit's MKLocalSearch, etc.). Returning
        // plain text — not JSON — keeps the model's reading of the result
        // simple and matches the way the rest of its training data looks.
        let results = mapItems(arguments: arguments)
        return "There are these \(arguments.pointOfInterest) in \(landmark.name): \(results.joined(separator: ", "))"
    }

    // MARK: Helpers

    @MainActor
    func recordLookup(arguments: Arguments) {
        lookupHistory.append(Lookup(history: arguments))
    }

    private func mapItems(arguments: Arguments) -> [String] {
        // Stand-in: a real tool would query SwiftData / MapKit / a service.
        // Make sure the data path is Sendable-clean — Tool calls run off the
        // main actor.
        return ["Sample A", "Sample B", "Sample C"]
    }
}

// MARK: - Side-state types used by the view

extension FindPointsOfInterestTool {

    /// Comma-separated list of all categories. Interpolated into the session
    /// `Instructions` so the model knows which categories are valid without
    /// us having to hand-write that text.
    static var categories: String {
        Category.allCases.map(\.rawValue).joined(separator: ", ")
    }

    /// One row in the SwiftUI `ForEach` that renders the searches the model
    /// is currently doing. Identifiable so the list animates cleanly.
    struct Lookup: Identifiable {
        let id = UUID()
        let history: FindPointsOfInterestTool.Arguments
    }
}

// MARK: - View binding (sketch)

/*
struct ItineraryPlanningView: View {
    let planner: ItineraryPlanner

    var body: some View {
        VStack(alignment: .leading) {
            Label("Planning itinerary…", systemImage: "sparkles")
                .font(.largeTitle).fontWeight(.bold)
                .symbolEffect(.breathe, isActive: true)

            ForEach(planner.pointOfInterestTool.lookupHistory) { element in
                HStack {
                    Image(systemName: "location.magnifyingglass")
                    Text("Searching **\(element.history.pointOfInterest.rawValue)**…")
                }
                .transition(.blurReplace)
                .foregroundStyle(.secondary)
            }
            .animation(.default, value: planner.pointOfInterestTool.lookupHistory.count)
        }
    }
}
*/
