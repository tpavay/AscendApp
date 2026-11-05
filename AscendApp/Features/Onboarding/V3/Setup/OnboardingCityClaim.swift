import Foundation
import Observation

/// What the city screen says, for each thing it can know. Pure, so the copy is tested without a
/// view and the count line never reads a failed read as an empty city.
struct OnboardingCityClaimCopy: Equatable, Sendable {
    /// The badge's three lines: "#1 IN", the place, and the pill.
    let badgeKicker: String
    let badgePlace: String
    let badgePill: String
    let body: String
    /// Whether the climber has picked a city, which is what offers CONTINUE.
    let hasCity: Bool

    static let introduction = "Every city gets its own leaderboard. Easier to top your city than the world, and that's where most climbers start."

    init(selection: PostAuthLocationSelection?, count: CityClimberCount?) {
        badgeKicker = "#1 IN"
        hasCity = selection != nil

        guard let selection else {
            badgePlace = "YOUR CITY"
            badgePill = "OPEN"
            body = Self.introduction
            return
        }

        let city = selection.city
        switch count {
        case .climbers(0):
            badgePlace = city.uppercased()
            badgePill = "OPEN"
            body = "Nobody in \(city) has climbed yet. Your first climb makes you #1, and everyone after has to beat you."
        case .climbers(let climbers):
            badgePlace = city.uppercased()
            badgePill = "TAKE IT"
            body = climbers == 1 ? "1 climber in \(city) so far." : "\(climbers.formatted()) climbers in \(city) so far."
        case .unknown, nil:
            // No count means no claim about the city: the intro line and the generic badge stand.
            badgePlace = "YOUR CITY"
            badgePill = "OPEN"
            body = Self.introduction
        }
    }
}

/// The signed-out city screen's state: nothing picked, the typing field open, or a city picked
/// with the count of its climbers on the way.
@MainActor
@Observable
final class OnboardingCityClaimModel {
    enum Phase: Equatable {
        case prompt
        case typing
        case located(PostAuthLocationSelection, CityClimberCount?)
    }

    private(set) var phase: Phase

    @ObservationIgnored private let reader: any CityClimberCountReading

    init(
        reader: any CityClimberCountReading = FirestoreCityClimberCountReader(),
        initialCity: PreAuthOnboardingCity? = nil
    ) {
        self.reader = reader
        phase = initialCity.map { .located($0.selection, nil) } ?? .prompt
    }

    var selection: PostAuthLocationSelection? {
        if case .located(let selection, _) = phase { selection } else { nil }
    }

    var copy: OnboardingCityClaimCopy {
        switch phase {
        case .prompt, .typing: OnboardingCityClaimCopy(selection: nil, count: nil)
        case .located(let selection, let count): OnboardingCityClaimCopy(selection: selection, count: count)
        }
    }

    func startTyping() {
        phase = .typing
    }

    func stopTyping() {
        if case .typing = phase { phase = .prompt }
    }

    /// Shows the picked city at once and fills its count in when the server answers. A city the
    /// climber picks again while the answer is on the way keeps only the newest answer.
    func claim(_ selection: PostAuthLocationSelection) async {
        phase = .located(selection, nil)
        let count = await reader.count(for: selection)
        guard case .located(let current, _) = phase, current == selection else { return }
        phase = .located(selection, count)
    }

    /// Fetches the count for a city restored from the answers.
    func refreshCount() async {
        guard case .located(let selection, nil) = phase else { return }
        await claim(selection)
    }
}
