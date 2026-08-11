enum PublicProfileAchievementPresentation: Equatable {
    case hidden
    case visible(ProfileAchievementCounts)

    init(achievements: ProfileAchievementCounts, isOtherLoading: Bool) {
        if isOtherLoading || !achievements.hasAny {
            self = .hidden
        } else {
            self = .visible(achievements)
        }
    }
}
