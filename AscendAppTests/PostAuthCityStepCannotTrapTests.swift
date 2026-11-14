import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// App Review rejected 1.3.0 (build 2026111301) under Guideline 2.1(a) on 2026-11-14: the reviewer
/// typed "Paris" on "Where are you climbing from?", Apple Maps answered "City search failed. Try
/// again.", and CONTINUE stayed disabled - the one control that led out - so they could not get into
/// the app.
///
/// The step is optional by promise ("You can change this later in profile"), so a failed search is
/// never a reason to hold a climber here. These tests fail the search on purpose, through the same
/// seam Apple Maps sits behind, and read what the real screen offers.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct PostAuthCityStepCannotTrapTests {
    private static let screenSize = CGSize(width: 390, height: 844)

    /// What the reviewer's device did: Apple Maps could not be reached.
    private struct AppleMapsUnreachable: Error {}

    @MainActor
    private final class FakeCitySource: PostAuthCitySuggestionSource {
        var onResult: ((Result<[PostAuthCitySearchSuggestion], any Error>) -> Void)?
        var searchResult: Result<[PostAuthCitySearchSuggestion], any Error>
        var resolveResult: Result<PostAuthLocationSelection?, any Error> = .success(nil)
        private(set) var fragments: [String] = []

        init(searchResult: Result<[PostAuthCitySearchSuggestion], any Error>) {
            self.searchResult = searchResult
        }

        func search(fragment: String) {
            fragments.append(fragment)
            guard !fragment.isEmpty else { return }
            onResult?(searchResult)
        }

        func resolve(_ suggestion: PostAuthCitySearchSuggestion) async throws -> PostAuthLocationSelection? {
            try resolveResult.get()
        }
    }

    private static let paris = PostAuthLocationSelection(city: "Paris", region: "Ile-de-France", countryCode: "FR", countryName: "France")
    private static let parisSuggestion = PostAuthCitySearchSuggestion(id: "paris", title: "Paris", subtitle: "France")

    private static func failedSearchModel() -> PostAuthCitySearchModel {
        let model = PostAuthCitySearchModel(source: FakeCitySource(searchResult: .failure(AppleMapsUnreachable())))
        model.query = "Paris"
        return model
    }

    // MARK: - The screen

    @Test
    func aFailedSearchLeavesTheClimberAWayOnThatSavesNothing() async throws {
        let model = Self.failedSearchModel()
        #expect(model.errorMessage == "City search failed. Try again.")

        var continued = 0
        let authVM = AuthenticationViewModel(observesFirebaseAuth: false)
        let screen = PostAuthLocationScreen(
            stage: .location,
            citySearch: model,
            onBack: {},
            onContinue: { continued += 1 }
        )
        .frame(width: Self.screenSize.width, height: Self.screenSize.height)
        .environment(authVM)
        .environment(\.colorScheme, .dark)

        try await RenderedScreen.host(screen, size: Self.screenSize) { screen in
            let copy = try await screen.copy { $0.contains("city search failed") }
            #expect(copy.contains("where are you"), "The step the reviewer was stuck on. On-screen text: \(copy)")
            #expect(copy.contains("city search failed"))
            #expect(copy.contains("skip for now"), "Nothing on the screen leads out. On-screen text: \(copy)")
            _ = try screen.photograph(named: "post-auth-city-step-failed-search-skip", scale: 2)

            // CONTINUE is rightly dead: there is no city to save.
            let continueButton = try #require(
                accessibilityElements(under: screen.root).first { $0.accessibilityLabel == "CONTINUE" }
            )
            #expect(continueButton.accessibilityTraits.contains(.notEnabled))

            try activateAccessibilityElement(labelled: "SKIP FOR NOW", in: screen.root)
            try await screen.settle(.turns(4))
        }

        #expect(continued == 1, "Skipping the city moves the climber on.")
        #expect(authVM.errorMessage == nil, "Skipping writes nothing, so nothing can fail.")
    }

    @Test
    func theSkipIsThereBeforeAnySearchHasFailedToo() async throws {
        // Apple Maps can also hang without ever answering, which draws no error at all.
        let model = PostAuthCitySearchModel(source: FakeCitySource(searchResult: .success([])))
        let screen = PostAuthLocationScreen(stage: .location, citySearch: model, onBack: {}, onContinue: {})
            .frame(width: Self.screenSize.width, height: Self.screenSize.height)
            .environment(AuthenticationViewModel(observesFirebaseAuth: false))
            .environment(\.colorScheme, .dark)

        try await RenderedScreen.host(screen, size: Self.screenSize) { screen in
            let copy = try await screen.copy { $0.contains("where are you") }
            #expect(copy.contains("skip for now"))
            #expect(
                copy.contains("current location") && copy.contains("search city"),
                "The city feature is still here for a climber whose search works. On-screen text: \(copy)"
            )
        }
    }

    // MARK: - The v3 screen

    @Test
    func theV3CityScreenKeepsItsSkipWhenTheSearchFails() async throws {
        let defaults = try #require(UserDefaults(suiteName: "post-auth-city-step-cannot-trap"))
        defaults.removePersistentDomain(forName: "post-auth-city-step-cannot-trap")
        let coordinator = OnboardingV3Coordinator(store: PreAuthOnboardingStore(userDefaults: defaults), startingAt: .claimCity)
        let model = OnboardingCityClaimModel(reader: UnreachableCityCount())
        model.startTyping()
        let screen = OnboardingClaimCityScreen(coordinator: coordinator, model: model, search: Self.failedSearchModel())
            .environment(\.onboardingV3Coordinator, coordinator)
            .background(OnboardingV3Palette.background.ignoresSafeArea())

        try await RenderedScreen.host(screen, size: Self.screenSize) { screen in
            let copy = try await screen.copy { $0.contains("city search failed") }
            #expect(copy.contains("city search failed"), "On-screen text: \(copy)")
            #expect(copy.contains("skip"), "Nothing on the screen leads out. On-screen text: \(copy)")

            try activateAccessibilityElement(in: screen.root) { $0.accessibilityLabel == "Skip" }
            try await screen.settle(.turns(4))
        }

        #expect(coordinator.step != .claimCity, "Skip moves the climber on.")
        #expect(coordinator.answers.city == nil)
    }

    private struct UnreachableCityCount: CityClimberCountReading {
        func count(for selection: PostAuthLocationSelection) async -> CityClimberCount { .unknown }
    }

    // MARK: - The search

    @Test
    func aFailedSearchSaysSoAndOffersNothing() {
        let model = Self.failedSearchModel()

        #expect(model.errorMessage == "City search failed. Try again.")
        #expect(model.suggestions.isEmpty)
        #expect(!model.isSearching)
    }

    @Test
    func aSearchThatWorksAgainClearsTheFailure() {
        let source = FakeCitySource(searchResult: .failure(AppleMapsUnreachable()))
        let model = PostAuthCitySearchModel(source: source)
        model.query = "Paris"
        #expect(model.errorMessage != nil)

        source.searchResult = .success([Self.parisSuggestion])
        model.query = "Paris, "

        #expect(model.errorMessage == nil)
        #expect(model.suggestions == [Self.parisSuggestion])
    }

    @Test
    func aLookupThatFailsSaysSoAndKeepsTheSearchOpen() async {
        let source = FakeCitySource(searchResult: .success([Self.parisSuggestion]))
        source.resolveResult = .failure(AppleMapsUnreachable())
        let model = PostAuthCitySearchModel(source: source)
        model.query = "Paris"

        let selection = await model.resolve(Self.parisSuggestion)

        #expect(selection == nil)
        #expect(model.errorMessage == "City search failed. Try a different search.")
        #expect(!model.isResolving)
    }

    @Test
    func aSearchThatWorksStillResolvesACity() async {
        let source = FakeCitySource(searchResult: .success([Self.parisSuggestion]))
        source.resolveResult = .success(Self.paris)
        let model = PostAuthCitySearchModel(source: source)
        model.query = "Paris"
        #expect(model.suggestions == [Self.parisSuggestion])

        let selection = await model.resolve(Self.parisSuggestion)

        #expect(selection == Self.paris)
        #expect(model.query == Self.paris.profileDisplayText)
        #expect(model.suggestions.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test
    func aSuggestionWithNoCityAsksForAnotherResult() async {
        let source = FakeCitySource(searchResult: .success([Self.parisSuggestion]))
        source.resolveResult = .success(nil)
        let model = PostAuthCitySearchModel(source: source)

        let selection = await model.resolve(Self.parisSuggestion)

        #expect(selection == nil)
        #expect(model.errorMessage == "Choose a city result.")
    }

    @Test
    func suggestionsAreDedupedAndCappedAtFive() {
        let found = (0..<8).map { PostAuthCitySearchSuggestion(id: "\($0 / 2)", title: "City \($0)", subtitle: "") }
        let model = PostAuthCitySearchModel(source: FakeCitySource(searchResult: .success(found)))
        model.query = "City"

        #expect(model.suggestions.map(\.id) == ["0", "1", "2", "3"])
    }
}
