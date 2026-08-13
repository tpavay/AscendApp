import Foundation

/// The content and progress drawn by the shared coach-mark overlay.
struct CoachMarkPresentation: Equatable {
    let title: String
    let message: String
    let stepCount: Int
    let stepIndex: Int
    let passedStepIndices: Set<Int>
    let primaryActionTitle: String
    let showsSkip: Bool
    /// A target that already carries its own accent outline can opt out of a second ring.
    /// The backdrop punch-out remains active either way.
    let drawsSpotlightRing: Bool

    init(
        title: String,
        message: String,
        stepCount: Int,
        stepIndex: Int,
        passedStepIndices: Set<Int> = [],
        primaryActionTitle: String,
        showsSkip: Bool,
        drawsSpotlightRing: Bool = true
    ) {
        self.title = title
        self.message = message
        self.stepCount = stepCount
        self.stepIndex = stepIndex
        self.passedStepIndices = passedStepIndices
        self.primaryActionTitle = primaryActionTitle
        self.showsSkip = showsSkip
        self.drawsSpotlightRing = drawsSpotlightRing
    }
}
