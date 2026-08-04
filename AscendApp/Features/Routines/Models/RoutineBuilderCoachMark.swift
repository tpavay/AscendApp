import Foundation

/// The first-open walkthrough. Three spotlights, because dragging bars on a timeline is an
/// invented interaction and nothing on the screen announces itself as draggable.
/// The order is the screen's order - timeline, then the step row, then the + button - so the
/// spotlight only ever travels down.
enum RoutineBuilderCoachMark: Int, CaseIterable, Identifiable {
    case timeline
    case stepControl
    case add

    /// Device-local, so the walkthrough costs no schema and no rules change. Debug Tools
    /// clears it so the run can be watched more than once.
    static let seenStorageKey = "routineBuilderCoachMarksSeen"

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .timeline:
            return "Drag a block."
        case .add:
            return "Add another."
        case .stepControl:
            return "Tap to select."
        }
    }

    var message: String {
        switch self {
        case .timeline:
            return "Up and down for the level. Left and right for the time."
        case .add:
            return "Every new block lands Standard at level 1. Drag it from there."
        case .stepControl:
            return "The step type and Delete follow whichever block you tapped. Long-press a block to move it."
        }
    }

    var target: RoutineBuilderCoachMarkTarget {
        switch self {
        case .timeline:
            return .timeline
        case .stepControl:
            return .stepControl
        case .add:
            return .add
        }
    }

    var presentation: RoutineCoachMarkPresentation {
        RoutineCoachMarkPresentation(
            title: title,
            message: message,
            stepCount: RoutineBuilderCoachMark.allCases.count,
            stepIndex: rawValue,
            primaryActionTitle: isLast ? "Done" : "Next",
            showsSkip: true
        )
    }

    var next: RoutineBuilderCoachMark? {
        RoutineBuilderCoachMark(rawValue: rawValue + 1)
    }

    var isLast: Bool {
        next == nil
    }
}
