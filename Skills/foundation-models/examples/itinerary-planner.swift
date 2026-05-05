//
//  itinerary-planner.swift
//  Skills / foundation-models / examples
//
//  Reference implementation of an @Observable @MainActor planner that owns a
//  LanguageModelSession, streams a @Generable result, and exposes a partially
//  generated value plus an observable tool-history list for the SwiftUI layer.
//
//  Adapted from Apple's `FoundationModelsTripPlanner` sample to match the
//  Agenic Load-Balancer project's Swift 6 strict-concurrency conventions.
//
//  This file is documentation — copy snippets into the project, do not add it
//  to the Xcode target as-is.

import FoundationModels
import Observation

// MARK: - Output shape

@Generable
struct Itinerary: Equatable {
    @Guide(description: "An exciting name for the trip.")
    let title: String

    /// Restricting `destinationName` to a closed set keeps the model from
    /// inventing landmark names. Source the array from your repository so the
    /// schema stays in sync with the catalog.
    @Guide(.anyOf(ModelData.landmarkNames))
    let destinationName: String

    let description: String

    @Guide(description: "An explanation of how the itinerary meets the person's special requests.")
    let rationale: String

    @Guide(description: "A list of day-by-day plans.")
    @Guide(.count(3))
    let days: [DayPlan]
}

@Generable
struct DayPlan: Equatable {
    @Guide(description: "A unique and exciting title for this day plan.")
    let title: String
    let subtitle: String
    let destination: String

    @Guide(.count(3))
    let activities: [Activity]
}

@Generable
struct Activity: Equatable {
    let type: Kind
    let title: String
    let description: String
}

@Generable
enum Kind {
    case sightseeing
    case foodAndDining
    case shopping
    case hotelAndLodging
}

// MARK: - Planner

@Observable
@MainActor
final class ItineraryPlanner {
    /// The streaming partial. SwiftUI binds to this directly via `@Observable`.
    /// Every field is `Optional` until the model emits it.
    private(set) var itinerary: Itinerary.PartiallyGenerated?

    /// Exposed so the view can render a "Searching cafés…" badge list while
    /// the model is mid-generation. Keeping the tool reference public lets the
    /// view observe the tool's lookup history without us needing to mirror it
    /// onto the planner.
    private(set) var pointOfInterestTool: FindPointsOfInterestTool

    /// Private — sessions are not Sendable and only exist on `@MainActor`.
    private var session: LanguageModelSession

    /// Surfaced to the view so a `MessageView` can show the user-facing copy
    /// (`error.localizedDescription`). Foundation Models throws on guard-rail
    /// violations, so never silently swallow.
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
                Here is a description of \(landmark.name) for your reference \
                when considering what activities to generate:
                """
                landmark.description
            }
        )
        self.pointOfInterestTool = pointOfInterestTool
    }

    /// Build the itinerary. Call from the view inside a `Task` and surface
    /// errors via the planner's `error` property — see the call site pattern
    /// at the bottom of this file.
    func suggestItinerary(dayCount: Int) async throws {
        let stream = session.streamResponse(
            generating: Itinerary.self,
            includeSchemaInPrompt: false,                 // schema is in the macro
            options: GenerationOptions(sampling: .greedy) // reproducible
        ) {
            "Generate a \(dayCount)-day itinerary to \(landmark.name)."
            "Give it a fun title and description."
            "Here is an example, but don't copy it:"
            Itinerary.exampleTripToJapan
        }

        for try await partialResponse in stream {
            self.itinerary = partialResponse.content
        }
    }

    /// Call from `.task` on the screen so the model is warm when the user
    /// taps the generate button. Drops first-token latency by ~1s on a cold
    /// session.
    func prewarm() {
        session.prewarm()
    }
}

// MARK: - View call site (sketch)

/*
struct LandmarkTripView: View {
    @State private var planner: ItineraryPlanner?
    @State private var requestedItinerary = false
    let landmark: Landmark

    var body: some View {
        if let error = planner?.error {
            MessageView(error: error, landmark: landmark)
        } else {
            ScrollView {
                if !requestedItinerary {
                    LandmarkDescriptionView(landmark: landmark)
                } else if let itinerary = planner?.itinerary {
                    ItineraryView(landmark: landmark, itinerary: itinerary).padding()
                } else if let planner {
                    ItineraryPlanningView(landmark: landmark, planner: planner)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ItineraryButton { try await requestItinerary() }
            }
            .task {
                planner = ItineraryPlanner(landmark: landmark)
                planner?.prewarm()                       // warm before user taps
            }
        }
    }

    func requestItinerary() async throws {
        requestedItinerary = true
        do {
            try await planner?.suggestItinerary(dayCount: 3)
        } catch {
            planner?.error = error                       // surface, don't swallow
        }
    }
}
*/

// MARK: - Few-shot example value

extension Itinerary {
    /// A literal example value passed into the user prompt as a few-shot
    /// demonstration. Concrete values steer the model far better than prose
    /// describing the format.
    static let exampleTripToJapan = Itinerary(
        title: "Onsen Trip to Japan",
        destinationName: "Mt. Fuji",
        description: "Sushi, hot springs, and ryokan with a toddler!",
        rationale: """
            You are traveling with a child, so climbing Mt. Fuji is probably \
            not an option, but there is lots to do around Kawaguchiko Lake, \
            including Fujikyu. I recommend staying in a ryokan because you \
            love hotsprings.
            """,
        days: [
            DayPlan(
                title: "Sushi and Shopping Near Kawaguchiko",
                subtitle: "Spend your final day enjoying sushi and souvenir shopping.",
                destination: "Kawaguchiko Lake",
                activities: [
                    Activity(type: .foodAndDining,
                             title: "The Restaurant serving Sushi",
                             description: "Visit an authentic sushi restaurant for lunch."),
                    Activity(type: .shopping,
                             title: "The Plaza",
                             description: "Enjoy souvenir shopping at various shops."),
                    Activity(type: .sightseeing,
                             title: "The Beautiful Cherry Blossom Park",
                             description: "Admire the beautiful cherry blossom trees in the park.")
                ]
            )
        ]
    )
}
