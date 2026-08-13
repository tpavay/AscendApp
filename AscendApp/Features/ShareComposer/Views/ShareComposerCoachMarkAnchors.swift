import SwiftUI

typealias ShareComposerCoachMarkAnchorKey = CoachMarkAnchorKey<ShareComposerCoachMarkTarget>

extension View {
    func shareComposerCoachMarkTarget(_ target: ShareComposerCoachMarkTarget) -> some View {
        coachMarkTarget(target)
    }
}
