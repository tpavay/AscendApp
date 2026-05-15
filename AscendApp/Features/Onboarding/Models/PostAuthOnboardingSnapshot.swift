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
}
