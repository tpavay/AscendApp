import SwiftUI

/// A landmark's marker on the globe: a tier-colored dot, nothing more. Numbers on
/// the globe mean one thing only, a cluster of N climbs; completion counts live on
/// the card. The two states a dot still carries: the First Ascent mark inside it
/// when nobody has finished the climb, and the viewer's own check on the shoulder
/// once they have. A coming-soon climb is a dimmed dashed ring with a lock. Settled
/// by the captain across the two dev-build rounds on 2026-09-21.
struct ClimbMarkerView: View {
    let climb: Climb
    /// Distinct climbers who have completed it, or nil until the boards have answered.
    /// Only zero changes the drawing (the open First Ascent); the number is never shown.
    let completedClimberCount: Int?
    let isCompleted: Bool
    let isHighlighted: Bool

    /// The dot's diameter. `ClimbMapClustering.overlapDistance` is derived from it.
    static let size: CGFloat = 22

    private var tierColor: Color {
        climb.tier.color
    }

    private var isFirstAscentOpen: Bool {
        climb.isAvailable && !isCompleted && completedClimberCount == 0
    }

    var body: some View {
        ZStack {
            if isHighlighted {
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                    .frame(width: Self.size + 8, height: Self.size + 8)
            }

            dot

            if isFirstAscentOpen {
                FirstAscentInlineMark(size: 15)
            } else if climb.isComingSoon {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: Self.size + 12, height: Self.size + 12)
        .overlay(alignment: .topTrailing) {
            if isCompleted {
                completedBadge
            }
        }
        .scaleEffect(isHighlighted ? 1.1 : 1)
        .opacity(climb.isComingSoon ? 0.72 : 1)
        .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private var dot: some View {
        if climb.isComingSoon {
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: Self.size, height: Self.size)
                .overlay {
                    Circle()
                        .strokeBorder(tierColor, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                }
        } else if isFirstAscentOpen {
            // The mark needs a dark field to read; the ring keeps the tier.
            Circle()
                .fill(Color.black.opacity(0.7))
                .frame(width: Self.size, height: Self.size)
                .overlay {
                    Circle()
                        .strokeBorder(tierColor, lineWidth: 2)
                }
        } else {
            Circle()
                .fill(tierColor)
                .frame(width: Self.size, height: Self.size)
                .overlay {
                    Circle()
                        .strokeBorder(.black.opacity(0.35), lineWidth: 1.5)
                }
        }
    }

    private var completedBadge: some View {
        Circle()
            .fill(Color.accent)
            .frame(width: 14, height: 14)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.88))
            }
            .overlay {
                Circle()
                    .strokeBorder(.black.opacity(0.6), lineWidth: 1)
            }
            .offset(x: -1, y: 1)
    }

    /// What the marker says to assistive technology: the count is spoken here even
    /// though it is never drawn, because a reader cannot open the card to find it.
    static func accessibilityDescription(
        climb: Climb,
        completedClimberCount: Int?,
        isCompleted: Bool
    ) -> String {
        if climb.isComingSoon {
            return "Coming soon climb, \(climb.displayLocation)"
        }
        var parts = ["\(climb.name), \(climb.displayLocation)"]
        if let completedClimberCount {
            parts.append(completedClimberCount == 0
                ? "First Ascent open"
                : "\(completedClimberCount) \(completedClimberCount == 1 ? "climber" : "climbers") completed")
        }
        if isCompleted {
            parts.append("you completed it")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Marker States") {
    HStack(spacing: 22) {
        VStack(spacing: 8) {
            ClimbMarkerView(climb: .preview, completedClimberCount: 12, isCompleted: false, isHighlighted: false)
            Text("Available").font(.caption2)
        }
        VStack(spacing: 8) {
            ClimbMarkerView(climb: .preview, completedClimberCount: 0, isCompleted: false, isHighlighted: false)
            Text("FA open").font(.caption2)
        }
        VStack(spacing: 8) {
            ClimbMarkerView(climb: .preview, completedClimberCount: 49, isCompleted: true, isHighlighted: false)
            Text("You did it").font(.caption2)
        }
        VStack(spacing: 8) {
            ClimbMarkerView(climb: .previewComingSoon, completedClimberCount: nil, isCompleted: false, isHighlighted: false)
            Text("Coming").font(.caption2)
        }
        VStack(spacing: 8) {
            ClimbMarkerView(climb: .preview, completedClimberCount: nil, isCompleted: false, isHighlighted: true)
            Text("Selected").font(.caption2)
        }
    }
    .padding(40)
    .background(Color(hex: "07101B"))
    .preferredColorScheme(.dark)
}
