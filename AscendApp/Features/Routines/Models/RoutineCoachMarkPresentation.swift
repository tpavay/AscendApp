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
}
