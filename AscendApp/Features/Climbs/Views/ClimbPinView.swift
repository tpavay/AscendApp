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
            token: isCompleted ? .mapPinFill : .mapPin,
            pointSize: pinSize
        )
        .foregroundStyle(pinColor)
    }

    private var pinColor: Color {
        return tierColor
    }

    private var shadowColor: Color {
        if isCompleted {
            return tierColor
        }

        return tierColor
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
            .fill(.white.opacity(0.24))
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
            ClimbPinView(climb: .preview, isCompleted: false, isHighlighted: true)
            Text("Selected").font(.caption2)
        }
    }
    .padding(40)
    .background(Color(hex: "07101B"))
    .preferredColorScheme(.dark)
}
