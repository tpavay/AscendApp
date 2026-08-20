import Foundation

struct PostAuthOnboardingSnapshot: Codable, Equatable {
    var currentStage: PostAuthOnboardingStage
    var completedStages: Set<PostAuthOnboardingStage>
    var isComplete: Bool
    var startedAt: Date
    var completedAt: Date?

    init(
        currentStage: PostAuthOnboardingStage = .first,
        completedStages: Set<PostAuthOnboardingStage> = [],
        isComplete: Bool = false,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.currentStage = currentStage
        self.completedStages = completedStages
        self.isComplete = isComplete
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    /// Decodes a snapshot written by a build whose stage list differed from this
    /// one's, dropping identifiers this build no longer knows.
    ///
    /// The synthesised `Codable` would throw on the first unrecognised stage, and
    /// throwing here is not a small failure: `PostAuthOnboardingStore` falls back
    /// to `legacySnapshot(from:)`, a one-time migration that resets `isComplete`
    /// to false and discards every completed stage. `markComplete` writes
    /// `Set(PostAuthOnboardingStage.allCases)`, so *every* finished climber's
    /// snapshot names every stage that existed when they finished - which means
    /// removing a case without this would drop the entire installed base back
    /// into onboarding on the update that removed it. An iOS binary cannot be
    /// rolled back, so that has no undo.
    ///
    /// A `currentStage` that no longer exists falls back to `.first`; the rest of
    /// the normalisation is `PostAuthOnboardingCoordinator`'s job, which already
    /// advances past every stage the climber has completed.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let storedCurrentStage = try container.decode(String.self, forKey: .currentStage)
        currentStage = PostAuthOnboardingStage(rawValue: storedCurrentStage) ?? .first

        let storedCompletedStages = try container.decode(Set<String>.self, forKey: .completedStages)
        completedStages = Set(storedCompletedStages.compactMap(PostAuthOnboardingStage.init(rawValue:)))

        isComplete = try container.decode(Bool.self, forKey: .isComplete)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}
