import SwiftUI

/// A ghost's name as the Mountain prints it over the athlete's head, drawn as a chip: the dot is
/// the ghost's own colour (`MountainSceneController` paints the personal best gold and the pacer
/// pale blue), and the words are the labels the climb itself carries.
struct SellGhostLabelChip: View {
    enum Kind {
        case personalBest
        case pacer(stepsPerMinute: Double)

        /// The label the Mountain's ghost carries, so the chip never drifts from the real one.
        var label: String {
            switch self {
            // The personal best ghost's label, as `AscendMountainRace.ghosts` names it.
            case .personalBest: "YOUR BEST"
            case .pacer(let stepsPerMinute): MountainGhost.pacer(stepsPerMinute: stepsPerMinute).label
            }
        }

        var dot: Color {
            switch self {
            case .personalBest: Color(red: 0.83, green: 0.69, blue: 0.22)
            case .pacer: Color(red: 0.75, green: 0.9, blue: 1)
            }
        }
    }

    let kind: Kind
    @ScaledMetric(relativeTo: .caption) private var scaledSize: CGFloat = 12

    /// The label stops at 20 pt, where the smallest phone still holds the pacer's chip whole beside
    /// a phone at its smallest.
    private var size: CGFloat { min(scaledSize, 20) }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(kind.dot).frame(width: 9, height: 9)
            Text(kind.label)
                .font(.custom("Montserrat-Bold", fixedSize: size))
                .tracking(size * 0.06)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(OnboardingV3Palette.controlFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: "2E2E2E"), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.label.capitalized)
    }
}
