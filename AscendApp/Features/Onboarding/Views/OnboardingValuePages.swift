import SwiftUI

enum OnboardingValuePages {
    static let all: [OnboardingValuePage] = [
        OnboardingValuePage(
            id: "engagement",
            headline: "Never get bored\non the climb.",
            subtitle: "Every climb becomes a race that holds your attention from step one.",
            heroImageName: "OnboardingEngagementHero",
            background: .solid(Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)),
            heroPresentation: .fullBleed
        ),
        OnboardingValuePage(
            id: "tracking",
            headline: "Never lose a\nworkout again.",
            subtitle: "Every climb gets logged forever — steps, time, and all the data you actually want.",
            heroImageName: "OnboardingWorkoutScreen",
            background: .solid(Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)),
            heroPresentation: .fullBleed
        ),
        OnboardingValuePage(
            id: "progress",
            headline: "Watch yourself\nget better.",
            subtitle: "Every climb feeds records, best efforts, and trends. Watch them all climb.",
            heroImageName: "OnboardingProgressHero",
            background: .solid(Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)),
            heroPresentation: .fullBleed
        ),
        OnboardingValuePage(
            id: "consistency",
            headline: "Always have a reason\nto come back.",
            subtitle: "Ranks to defend. Climbs to claim. Routines to run. Records to break.",
            heroImageName: "OnboardingConsistencyHero",
            background: .solid(Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)),
            heroPresentation: .fullBleed
        )
    ]
}
