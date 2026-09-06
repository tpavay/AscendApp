import SwiftUI

/// The lime/blue proportional bar every comparison row sits on. Lime is always the viewer,
/// blue is always the other climber - the screen's ownership vocabulary, rendered as a
/// quantity. A side holding nothing yields the whole bar to the other, which is a competitive
/// fact in one glance.
struct ProfileComparisonStatBar: View {
    let viewerValue: Double
    let otherValue: Double
    var isLoadingOtherValue = false

    private var viewerRatio: CGFloat {
        if isLoadingOtherValue {
            return 0.5
        }
        let total = viewerValue + otherValue
        guard total > 0 else { return 0.5 }
        return CGFloat(max(min(viewerValue / total, 1), 0))
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.ascendAccent)
                    .frame(width: max(geometry.size.width * viewerRatio, 0))

                if isLoadingOtherValue {
                    Rectangle()
                        .fill(ProfileVisualStyle.skeletonFill)
                        .ascendSkeletonShimmer()
                } else {
                    Rectangle()
                        .fill(ProfileVisualStyle.opponentBlue)
                }
            }
            .clipShape(Capsule(style: .continuous))
            .opacity(viewerValue + otherValue > 0 || isLoadingOtherValue ? 1 : 0.35)
        }
        .frame(height: 5)
    }
}
