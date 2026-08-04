import Foundation

/// What a coach mark spotlights.
///
/// Deliberately separate from `RoutineBuilderCoachMark`, which is the first-open walkthrough's
/// step order: the window mark points at a surface no walkthrough step does, and adding it to
/// that enum would put a fourth dot in a three-step run it can never appear in.
enum RoutineBuilderCoachMarkTarget: Hashable {
    case timeline
    case stepControl
    case add
    case overview
}
