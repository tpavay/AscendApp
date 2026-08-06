import Foundation

/// The coach mark that fires the first time a routine outgrows the screen.
///
/// It is not a fourth step of the first-open walkthrough. That run is driven by
/// `RoutineBuilderCoachMark.allCases`, and a new routine cannot have enough intervals to reach
/// this one, so it carries its own trigger, its own storage key and a single Got it.
enum RoutineWindowCoachMark {
    /// Device-local, like the walkthrough's. Debug Tools clears it so it can be watched again.
    static let seenStorageKey = "routineBuilderWindowCoachMarkSeen"

    static let title = "Drag the window."
    static let message = "Change which intervals you're viewing."

    static let presentation = RoutineCoachMarkPresentation(
        title: title,
        message: message,
        stepCount: 1,
        stepIndex: 0,
        primaryActionTitle: "Got it",
        showsSkip: false,
        // The window it names is already a lime rounded rect. A spotlight ring around the strip
        // put a second lime outline around the first, and the box in a box obscured the one
        // element the card exists to point at. This mark alone opts out; the walkthrough's
        // three targets carry no outline of their own and keep theirs.
        drawsSpotlightRing: false
    )

    /// Once, the first time the window arrives - and never over the first-open walkthrough,
    /// which owns the screen until it is done.
    static func shouldPresent(
        isWindowEngaged: Bool,
        hasSeen: Bool,
        isCoachMarkOnScreen: Bool
    ) -> Bool {
        isWindowEngaged && !hasSeen && !isCoachMarkOnScreen
    }
}
