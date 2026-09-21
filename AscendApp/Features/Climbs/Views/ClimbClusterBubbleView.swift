import SwiftUI

/// A counted bubble standing in for several landmarks at world zoom. Colored by the
/// highest tier inside it, so a count still says what kind of climbs it gathers, and
/// checked when the viewer has claimed every one of them.
struct ClimbClusterBubbleView: View {
    let cluster: AscendMapCluster

    private var tierColor: Color {
        cluster.leadingTier.color
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.62))
                .frame(width: 38, height: 38)
                .overlay {
                    Circle()
                        .strokeBorder(tierColor, lineWidth: 2)
                }

            Text(cluster.count.formatted())
                .font(.montserratBold(size: 13))
                .foregroundStyle(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.horizontal, 6)
        }
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
                    .offset(x: 3, y: -3)
            }
        }
        .frame(width: 44, height: 44)
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
