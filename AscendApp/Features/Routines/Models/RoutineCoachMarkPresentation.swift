import Foundation

/// What a coach mark card says, so one overlay can draw both the first-open walkthrough and the
/// one-off window mark without knowing which of them it is holding.
struct RoutineCoachMarkPresentation: Equatable {
    let title: String
    let message: String
    /// How many dots the card shows. A mark that fires on its own trigger shows one.
    let stepCount: Int
    let stepIndex: Int
    let primaryActionTitle: String
    let showsSkip: Bool
    /// Whether the overlay outlines the spotlit target. Default yes - a mark points at a control
    /// that has no outline of its own, so the ring is what says *this one*. A mark opts out only
    /// when its target already draws a lime outline, because a second concentric one reads as a
    /// box in a box and hides the very thing the card is naming.
    ///
    /// The dim's punch-out is not this: the target stays lit either way.
    let drawsSpotlightRing: Bool

    init(
        title: String,
        message: String,
        stepCount: Int,
        stepIndex: Int,
        primaryActionTitle: String,
        showsSkip: Bool,
        drawsSpotlightRing: Bool = true
    ) {
        self.title = title
        self.message = message
        self.stepCount = stepCount
        self.stepIndex = stepIndex
        self.primaryActionTitle = primaryActionTitle
        self.showsSkip = showsSkip
        self.drawsSpotlightRing = drawsSpotlightRing
    }
}
