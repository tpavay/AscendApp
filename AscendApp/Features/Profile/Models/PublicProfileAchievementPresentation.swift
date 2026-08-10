enum PublicProfileAchievementPresentation: Equatable {
    case loading
    case hidden
    case visible(ProfileAchievementCounts)

    init(achievements: ProfileAchievementCounts, isOtherLoading: Bool) {
        if isOtherLoading {
            self = .loading
        } else if achievements.hasAny {
            self = .visible(achievements)
        } else {
            self = .hidden
        }
    }
}
