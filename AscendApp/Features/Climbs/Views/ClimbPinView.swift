import SwiftUI

struct ClimbPinView: View {
    let climb: Climb
    let isCompleted: Bool
    let isHighlighted: Bool

    private let pinSize: CGFloat = 18
    private let completedBadgeSize: CGFloat = 16
    private let completedBadgeLift: CGFloat = -6

    private var tierColor: Color {
        climb.tier.color
    }

    var body: some View {
        ZStack {
            if isCompleted {
                if isHighlighted {
                    completedSelectionRing
                }

                completedBadge
            } else {
                if isHighlighted {
                    availableSelectionGlow
                }

                pinIcon
            }
        }
        .frame(width: 34, height: 38, alignment: .bottom)
        .scaleEffect(isHighlighted ? 1.06 : 1)
        .shadow(
            color: shadowColor.opacity(isHighlighted ? 0.28 : 0.14),
            radius: isHighlighted ? 9 : 4,
            x: 0,
            y: 3
        )
    }

    private var pinIcon: some View {
        AppIcon(
            token: isCompleted || climb.isAvailable ? .mapPinFill : .mapPin,
            pointSize: pinSize
        )
        .foregroundStyle(pinColor)
        .opacity(climb.isComingSoon ? 0.42 : 1)
    }

    private var pinColor: Color {
        // Unclaimed climbs (available OR coming-soon) render in neutral grey.
        // Tier color is reserved for the completed-state check badge so the
        // grey-vs-color contrast becomes the user's at-a-glance "what have I
        // claimed?" signal.
        .white.opacity(0.55)
    }

    private var shadowColor: Color {
        if isCompleted {
            return tierColor
        }

        return .white.opacity(0.25)
    }

    private var completedBadge: some View {
        Circle()
            .fill(tierColor)
            .frame(width: completedBadgeSize, height: completedBadgeSize)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.88))
            }
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
            }
            .offset(y: completedBadgeLift)
    }

    private var completedSelectionRing: some View {
        Circle()
            .strokeBorder(.white.opacity(0.68), lineWidth: 1.2)
            .frame(width: completedBadgeSize + 6, height: completedBadgeSize + 6)
            .offset(y: completedBadgeLift)
    }

    private var availableSelectionGlow: some View {
        Circle()
            .fill((climb.isComingSoon ? Color.white.opacity(0.12) : Color.white.opacity(0.24)))
            .frame(width: 12, height: 12)
            .blur(radius: 0.8)
            .offset(y: -7)
    }

}

#Preview("Pin States") {
    HStack(spacing: 26) {
        VStack(spacing: 8) {
            ClimbPinView(climb: .preview, isCompleted: false, isHighlighted: false)
            Text("Available").font(.caption2)
        }
        VStack(spacing: 8) {
            ClimbPinView(climb: .preview, isCompleted: true, isHighlighted: false)
            Text("Completed").font(.caption2)
        }
        VStack(spacing: 8) {
            ClimbPinView(climb: .previewComingSoon, isCompleted: false, isHighlighted: false)
            Text("Coming").font(.caption2)
        }
        VStack(spacing: 8) {
            ClimbPinView(climb: .preview, isCompleted: false, isHighlighted: true)
            Text("Selected").font(.caption2)
        }
    }
    .padding(40)
    .background(Color(hex: "07101B"))
    .preferredColorScheme(.dark)
}
