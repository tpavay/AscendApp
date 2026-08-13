import SwiftUI

/// Where each feature's coach-mark targets are, published by the views being described.
struct CoachMarkAnchorKey<Target: Hashable>: PreferenceKey {
    static var defaultValue: [Target: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [Target: Anchor<CGRect>],
        nextValue: () -> [Target: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

extension View {
    /// Marks this view as the thing a coach mark spotlights.
    ///
    /// Transforming rather than setting, because the targets are not all siblings: the routine
    /// window mark's overview sits *inside* the subtree the walkthrough's timeline target wraps,
    /// and a modifier that writes the key outright would drop everything the subtree published -
    /// the nested mark would then draw a full dim with no spotlight at all.
    func coachMarkTarget<Target: Hashable>(_ target: Target) -> some View {
        transformAnchorPreference(
            key: CoachMarkAnchorKey<Target>.self,
            value: .bounds
        ) { targets, anchor in
            targets[target] = anchor
        }
    }
}
