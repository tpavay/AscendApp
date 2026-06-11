import Combine
import Foundation
@preconcurrency import MapKit

struct PostAuthLocationSelection: Equatable, Sendable {
    let city: String
    let region: String?
    let countryCode: String
    let countryName: String

    var title: String {
        city
    }

    var subtitle: String {
        [region, countryName]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
    }

    var profileDisplayText: String {
        if let region, !region.isEmpty {
            return "\(city), \(region)"
        }

        return "\(city), \(countryName)"
    }

    init?(placemark: MKPlacemark) {
        guard let city = placemark.locality?.trimmedLocationText,
              !city.isEmpty,
              let countryCode = placemark.isoCountryCode?.trimmedLocationText.uppercased(),
              countryCode.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil else {
            return nil
        }

        self.city = city
        self.region = placemark.administrativeArea?.trimmedLocationText
        self.countryCode = countryCode
        self.countryName = placemark.country?.trimmedLocationText
            ?? Locale.current.localizedString(forRegionCode: countryCode)
            ?? countryCode
    }
}

struct PostAuthCitySearchSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String

    init(id: String, title: String, subtitle: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }

    init(completion: MKLocalSearchCompletion) {
        let id = "\(completion.title)|\(completion.subtitle)"
        self.init(id: id, title: completion.title, subtitle: completion.subtitle)
    }
}

@MainActor
final class PostAuthCitySearchModel: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            updateCompleterQuery()
        }
    }

    @Published private(set) var suggestions: [PostAuthCitySearchSuggestion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isResolving = false
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var completionsByID: [String: MKLocalSearchCompletion] = [:]

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }

    func setSelectedLocation(_ selection: PostAuthLocationSelection) {
        query = selection.profileDisplayText
        suggestions = []
        isSearching = false
        errorMessage = nil
    }

    func resolve(_ suggestion: PostAuthCitySearchSuggestion) async -> PostAuthLocationSelection? {
        guard let completion = completionsByID[suggestion.id] else {
            errorMessage = "Choose a city result."
            return nil
        }

        isResolving = true
        errorMessage = nil

        defer {
            isResolving = false
        }

        do {
            let request = MKLocalSearch.Request(completion: completion)
            request.resultTypes = [.address]
            let response = try await MKLocalSearch(request: request).start()
            if let selection = response.mapItems.lazy.compactMap({ PostAuthLocationSelection(placemark: $0.placemark) }).first {
                setSelectedLocation(selection)
                return selection
            }

            errorMessage = "Choose a city result."
            return nil
        } catch {
            errorMessage = "City search failed. Try a different search."
            return nil
        }
    }

    private func updateSuggestions(from completions: [MKLocalSearchCompletion]) {
        var seenIDs = Set<String>()
        var nextCompletionsByID: [String: MKLocalSearchCompletion] = [:]
        let uniqueSuggestions = completions
            .map(PostAuthCitySearchSuggestion.init)
            .filter { suggestion in
                let isNew = seenIDs.insert(suggestion.id).inserted
                if isNew {
                    nextCompletionsByID[suggestion.id] = completions.first {
                        "\($0.title)|\($0.subtitle)" == suggestion.id
                    }
                }
                return isNew
            }
            .prefix(5)

        completionsByID = nextCompletionsByID
        suggestions = Array(uniqueSuggestions)
        isSearching = false
        errorMessage = nil
    }

    private func handleSearchFailure() {
        completionsByID = [:]
        suggestions = []
        isSearching = false
        errorMessage = "City search failed. Try again."
    }

    private func updateCompleterQuery() {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 2 else {
            completionsByID = [:]
            suggestions = []
            isSearching = false
            errorMessage = nil
            completer.queryFragment = ""
            return
        }

        isSearching = true
        errorMessage = nil
        completer.queryFragment = normalizedQuery
    }
}

extension PostAuthCitySearchModel: @preconcurrency MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        updateSuggestions(from: completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        handleSearchFailure()
    }
}

private extension String {
    var trimmedLocationText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
