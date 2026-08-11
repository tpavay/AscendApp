enum PublicProfileAchievementPresentation: Equatable {
    case hidden
    case visible(ProfileAchievementLadder)

    init(achievements: ProfileAchievementLadder, isOtherLoading: Bool) {
        if isOtherLoading || !achievements.hasAny {
            self = .hidden
        } else {
            self = .visible(achievements)
        }
    }
}
