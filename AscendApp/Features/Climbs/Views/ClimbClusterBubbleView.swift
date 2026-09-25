import SwiftUI

/// A pill standing in for several landmarks at world zoom, reading "N climbs" so the
/// number is never mistaken for a completion count. Colored by the highest tier
/// inside it, and checked when the viewer has claimed every one of them.
struct ClimbClusterBubbleView: View {
    let cluster: AscendMapCluster

    private var tierColor: Color {
        cluster.leadingTier.color
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tierColor)

            Text("\(cluster.count.formatted()) climbs")
                .font(.montserratBold(size: 11))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.66))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tierColor.opacity(0.9), lineWidth: 1.5)
        )
        .overlay(alignment: .topTrailing) {
            if cluster.isFullyCompleted {
                Circle()
                    .fill(tierColor)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(Color.black.opacity(0.88))
                    }
                    .offset(x: 5, y: -6)
            }
        }
        .shadow(color: tierColor.opacity(0.3), radius: 6, x: 0, y: 3)
    }
}

#Preview {
    ClimbClusterBubbleView(
        cluster: AscendMapCluster(
            id: "preview",
            coordinate: Climb.preview.coordinate,
            landmarks: [
                AscendMapLandmark(climb: .preview, state: .available, isHighlighted: false),
                AscendMapLandmark(climb: .previewComingSoon, state: .comingSoon, isHighlighted: false)
            ]
        )
    )
    .padding(40)
    .background(Color(hex: "07101B"))
    .preferredColorScheme(.dark)
}
