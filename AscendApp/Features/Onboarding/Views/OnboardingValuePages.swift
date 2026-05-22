import Foundation

enum OnboardingValuePages {
    static let all: [OnboardingValuePage] = [
        OnboardingValuePage(
            id: "global-climbs",
            headline: "Join The\nGlobal Climb",
            subtitle: "Discover climbs around the world and take them on from your own stair machine.",
            heroImageName: "OnboardingGlobalClimbsScreenshot",
            background: .image("OnboardingGlobalClimbsBackground"),
            heroScale: 1.34,
            heroYOffset: 48
        ),
        OnboardingValuePage(
            id: "leaderboards",
            headline: "See Where\nYou Stand",
            subtitle: "Push alongside past finishers, with ranks that update as you climb.",
            heroImageName: "OnboardingEmpireLeaderboardScreenshot",
            background: .image("OnboardingLeaderboardsBackground"),
            heroScale: 1.14,
            heroXOffset: -4,
            heroYOffset: 50,
            heroRotation: .degrees(0)
        ),
        OnboardingValuePage(
            id: "tracking",
            headline: "Track Every\nClimb",
            subtitle: "Save Live Climbs, import completed sessions from Apple Health, or log stair sessions manually in one place.",
            heroImageName: "OnboardingWorkoutsScreenshot",
            background: .image(
                "OnboardingWorkoutsBackground",
                dimmingOpacity: 0.12,
                topReadabilityOpacity: 0.08
            ),
            heroScale: 1.34,
            heroYOffset: 48
        ),
        OnboardingValuePage(
            id: "progress",
            headline: "Analyze Your\nProgress",
            subtitle: "See how your climbs are adding up, from new records to training trends and streaks.",
            heroImageName: "OnboardingProgressScreenshot",
            background: .image("OnboardingProgressBackground"),
            heroScale: 1.05,
            heroYOffset: -4
        )
    ]
}
