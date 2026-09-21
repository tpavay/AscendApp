import SwiftUI

/// A landmark's marker on the globe: a tier-colored disc that carries information,
/// not a pin. Inside it, how many climbers have completed the climb, or the First
/// Ascent mark when nobody has; on its shoulder, the check that says the viewer has.
/// A coming-soon climb is a dimmed ring with a lock. Settled by the captain on the
/// round-2 review: "we're going away from pins and actually showing information in
/// addition to the marker."
struct ClimbMarkerView: View {
    let climb: Climb
    /// Distinct climbers who have completed it, or nil until the boards have answered.
    let completedClimberCount: Int?
    let isCompleted: Bool
    let isHighlighted: Bool

    static let size: CGFloat = 30

    private var tierColor: Color {
        climb.tier.color
    }

    var body: some View {
        ZStack {
            if isHighlighted {
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                    .frame(width: Self.size + 8, height: Self.size + 8)
            }

            disc

            content
        }
        .frame(width: Self.size + 12, height: Self.size + 12)
        .overlay(alignment: .topTrailing) {
            if isCompleted {
                completedBadge
            }
        }
        .scaleEffect(isHighlighted ? 1.08 : 1)
        .opacity(climb.isComingSoon ? 0.72 : 1)
        .shadow(
            color: tierColor.opacity(isHighlighted ? 0.45 : 0.28),
            radius: isHighlighted ? 8 : 4,
            x: 0,
            y: 2
        )
    }

    private var disc: some View {
        Circle()
            .fill(Color.black.opacity(climb.isComingSoon ? 0.5 : 0.7))
            .frame(width: Self.size, height: Self.size)
            .overlay {
                Circle()
                    .strokeBorder(tierColor, style: StrokeStyle(lineWidth: 2, dash: climb.isComingSoon ? [3, 3] : []))
            }
    }

    @ViewBuilder
    private var content: some View {
        if climb.isComingSoon {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
        } else if let completedClimberCount {
            if completedClimberCount > 0 {
                Text(Self.countText(completedClimberCount))
                    .font(.montserratBold(size: completedClimberCount >= 1_000 ? 9 : 11))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: Self.size - 8)
            } else {
                FirstAscentInlineMark(size: 20)
            }
        } else {
            // Unread: the tier dot alone, so the marker never shows a number it has not read.
            Circle()
                .fill(tierColor)
                .frame(width: 8, height: 8)
        }
    }

    private var completedBadge: some View {
        Circle()
            .fill(tierColor)
            .frame(width: 15, height: 15)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.88))
            }
            .overlay {
                Circle()
                    .strokeBorder(.black.opacity(0.6), lineWidth: 1)
            }
            .offset(x: -2, y: 2)
    }

    /// "12", "999", "1.2k": the disc is small, so thousands compress.
    static func countText(_ count: Int) -> String {
        if count >= 1_000 {
            let thousands = Double(count) / 1_000
            let rounded = (thousands * 10).rounded() / 10
            return rounded == rounded.rounded()
                ? "\(Int(rounded))k"
                : "\(rounded.formatted(.number.precision(.fractionLength(1))))k"
        }
        return count.formatted()
    }

    /// What the marker says to assistive technology, mirroring what it draws.
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
            Text("12 done").font(.caption2)
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
            Text("Unread, selected").font(.caption2)
        }
    }
    .padding(40)
    .background(Color(hex: "07101B"))
    .preferredColorScheme(.dark)
}
