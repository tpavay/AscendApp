import SwiftUI

/// Compatibility names for the routine feature. The anchor plumbing and the renderer are shared
/// with Share Composer so neither feature can fork the card or spotlight UI.
typealias RoutineBuilderCoachMarkAnchorKey = CoachMarkAnchorKey<RoutineBuilderCoachMarkTarget>
typealias RoutineBuilderCoachMarkOverlay = CoachMarkOverlay

extension View {
    func routineCoachMarkTarget(_ target: RoutineBuilderCoachMarkTarget) -> some View {
        coachMarkTarget(target)
    }
}
