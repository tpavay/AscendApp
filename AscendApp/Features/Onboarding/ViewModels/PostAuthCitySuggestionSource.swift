import Foundation
@preconcurrency import MapKit

/// Where a city search gets its suggestions and its resolved city.
///
/// `PostAuthCitySearchModel` owns what a climber is told; this owns the network. The seam exists
/// because the one thing the screens above it cannot afford is to have only one behaviour: Apple
/// Maps is a network call, App Review's devices sit behind networks that refuse it, and a search
/// that fails must be reproducible without one (`PostAuthCityStepCannotTrapTests`).
@MainActor
protocol PostAuthCitySuggestionSource: AnyObject {
    /// Called with every set of suggestions the search produces, or with the error that ended it.
    var onResult: ((Result<[PostAuthCitySearchSuggestion], any Error>) -> Void)? { get set }

    /// Starts a search for `fragment`. An empty fragment cancels the search in flight.
    func search(fragment: String)

    /// The city a suggestion stands for, or `nil` when it has none (a street, a venue, a stale
    /// suggestion). Throws when the lookup itself fails.
    func resolve(_ suggestion: PostAuthCitySearchSuggestion) async throws -> PostAuthLocationSelection?
}

/// Apple Maps: `MKLocalSearchCompleter` for suggestions, `MKLocalSearch` for the chosen one.
@MainActor
final class MapKitCitySuggestionSource: NSObject, PostAuthCitySuggestionSource {
    var onResult: ((Result<[PostAuthCitySearchSuggestion], any Error>) -> Void)?

    private let completer = MKLocalSearchCompleter()
    private var completionsByID: [String: MKLocalSearchCompletion] = [:]

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }

    func search(fragment: String) {
        if fragment.isEmpty { completionsByID = [:] }
        completer.queryFragment = fragment
    }

    func resolve(_ suggestion: PostAuthCitySearchSuggestion) async throws -> PostAuthLocationSelection? {
        guard let completion = completionsByID[suggestion.id] else { return nil }

        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = [.address]
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.lazy.compactMap { PostAuthLocationSelection(placemark: $0.placemark) }.first
    }
}

extension MapKitCitySuggestionSource: @preconcurrency MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        var byID: [String: MKLocalSearchCompletion] = [:]
        var suggestions: [PostAuthCitySearchSuggestion] = []
        for completion in completer.results {
            let suggestion = PostAuthCitySearchSuggestion(completion: completion)
            guard byID[suggestion.id] == nil else { continue }
            byID[suggestion.id] = completion
            suggestions.append(suggestion)
        }

        completionsByID = byID
        onResult?(.success(suggestions))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        completionsByID = [:]
        onResult?(.failure(error))
    }
}
