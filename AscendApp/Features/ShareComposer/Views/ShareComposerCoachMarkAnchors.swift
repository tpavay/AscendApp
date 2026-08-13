import SwiftUI

struct ShareComposerCoachMarkAnchorKey: PreferenceKey {
    static let defaultValue: [ShareComposerCoachMarkTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [ShareComposerCoachMarkTarget: Anchor<CGRect>],
        nextValue: () -> [ShareComposerCoachMarkTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

extension View {
    func shareComposerCoachMarkTarget(_ target: ShareComposerCoachMarkTarget) -> some View {
        transformAnchorPreference(
            key: ShareComposerCoachMarkAnchorKey.self,
            value: .bounds
        ) { targets, anchor in
            targets[target] = anchor
        }
    }
}
