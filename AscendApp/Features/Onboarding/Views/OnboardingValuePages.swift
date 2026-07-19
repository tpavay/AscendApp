import SwiftUI

enum OnboardingValuePages {
    static let all: [OnboardingValuePage] = [
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
            subtitle: "Choose from 75 landmarks to climb and compete against others.",
            heroImageName: "OnboardingConsistencyHero",
            background: .solid(Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)),
            heroPresentation: .fullBleed,
            fullBleedHeroFrame: .landmarks
        )
    ]
}
