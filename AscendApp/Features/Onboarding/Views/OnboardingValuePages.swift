import SwiftUI

enum OnboardingValuePages {
    /// The purchase-inducing landmark count is a promise, so it is read off the
    /// catalogue rather than typed in. A catalogue that cannot be read drops the
    /// number instead of guessing one.
    static func pages(raceableLandmarkCount: Int) -> [OnboardingValuePage] {
        [
            OnboardingValuePage(
                id: "watch_yourself_get_better",
                headline: "Get fit with the stair stepper",
                subtitle: "Every climb feeds records, best efforts, and trends. Watch them all climb.",
                heroImageName: "OnboardingProgressHero",
                background: .solid(Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)),
                heroPresentation: .fullBleed,
                fullBleedHeroFrame: .progress
            ),
            OnboardingValuePage(
                id: "reason_to_come_back",
                headline: "Never get bored on the climb",
                subtitle: landmarkSubtitle(raceableLandmarkCount: raceableLandmarkCount),
                heroImageName: "OnboardingConsistencyHero",
                background: .solid(Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)),
                heroPresentation: .fullBleed,
                fullBleedHeroFrame: .landmarks
            )
        ]
    }

    static func landmarkSubtitle(raceableLandmarkCount: Int) -> String {
        guard raceableLandmarkCount > 0 else {
            return "Choose from real landmarks to climb and compete against others."
        }

        return "Choose from \(raceableLandmarkCount) landmarks to climb and compete against others."
    }

    @MainActor
    static var all: [OnboardingValuePage] {
        pages(raceableLandmarkCount: ClimbService.shared.raceableClimbCount)
    }
}
