import SwiftUI

struct RoutineBuilderCoachMarkAnchorKey: PreferenceKey {
    static let defaultValue: [RoutineBuilderCoachMarkTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [RoutineBuilderCoachMarkTarget: Anchor<CGRect>],
        nextValue: () -> [RoutineBuilderCoachMarkTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

extension View {
    /// Marks this view as the thing a coach mark spotlights.
    ///
    /// Transforming rather than setting, because the targets are not all siblings: the window
    /// mark's overview sits *inside* the subtree the walkthrough's timeline target wraps, and a
    /// modifier that writes the key outright would drop everything the subtree published - the
    /// nested mark would then draw a full dim with no spotlight at all.
    func routineCoachMarkTarget(_ target: RoutineBuilderCoachMarkTarget) -> some View {
        transformAnchorPreference(
            key: RoutineBuilderCoachMarkAnchorKey.self,
            value: .bounds
        ) { targets, anchor in
            targets[target] = anchor
        }
    }
}

/// Compatibility name for the routine feature. The renderer itself is shared with Share
/// Composer so neither feature can fork the card or spotlight UI.
typealias RoutineBuilderCoachMarkOverlay = CoachMarkOverlay
