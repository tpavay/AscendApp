import Foundation

enum OnboardingValuePages {
    static let all: [OnboardingValuePage] = [
        OnboardingValuePage(
            id: "global-climbs",
            headline: "Join The\nGlobal Climb",
            subtitle: "Discover climbs around the world and take them on from your own stair machine.",
            heroImageName: "OnboardingGlobalClimbsPhone",
            background: .image("OnboardingGlobalClimbsBackground"),
            heroScale: 1.05,
            heroYOffset: -4
        ),
        OnboardingValuePage(
            id: "leaderboards",
            headline: "See Where\nYou Stand",
            subtitle: "Push alongside past finishers, with ranks that update as you climb.",
            heroImageName: "OnboardingLeaderboardsPhone",
            background: .image("OnboardingLeaderboardsBackground"),
            heroScale: 1.14,
            heroXOffset: -4,
            heroYOffset: 50,
            heroRotation: .degrees(0)
        ),
        OnboardingValuePage(
            id: "tracking",
            headline: "Track Without\nBreaking Stride",
            subtitle: "Log focused climbs with a dark, minimal flow that keeps effort front and center.",
            heroImageName: "OnboardingGlobalClimbsPhone",
            background: .ambient(.tracking),
            heroScale: 1.02,
            heroYOffset: -8
        ),
        OnboardingValuePage(
            id: "progress",
            headline: "See Your\nProgress Rise",
            subtitle: "Turn every climb into records, trends, and stronger training decisions.",
            heroImageName: "OnboardingGlobalClimbsPhone",
            background: .ambient(.progress),
            heroScale: 1.02,
            heroYOffset: -8
        )
    ]
}
