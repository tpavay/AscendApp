import SwiftUI

/// The colours of an event's own pages. Pumpkin orange marks the season - its count, its days left,
/// its START CLIMBING - while lime keeps meaning earned, as it does everywhere else.
enum UnlockStyle {
    static let pumpkin = Color(hex: "#FF8A1F")
    static let pumpkinLight = Color(hex: "#FFB021")
    /// Text on orange.
    static let pumpkinInk = Color(hex: "#1A0D02")
    /// Text on lime.
    static let limeInk = Color(hex: "#0E1013")
    static let pageBackground = Color(hex: "#07050C")
    static let tileFill = Color(hex: "#120D1D")

    static let progressFill = LinearGradient(colors: [pumpkin, pumpkinLight], startPoint: .leading, endPoint: .trailing)

    /// The dim lime glow low behind the athlete's feet on every stage that shows them.
    static var stageGlow: some View {
        RadialGradient(colors: [Color(hex: "#1C240F"), .black], center: UnitPoint(x: 0.5, y: 0.72), startRadius: 0, endRadius: 210)
    }
}

/// One item on an event ladder: the item itself, its name, and what it takes. Earned items carry
/// a lime EARNED sash in the corner and an ON pill when worn; the next item on the ladder has a
/// dashed outline; the rest show a small lock.
struct UnlockItemTile: View {
    let item: UnlockItem
    let event: UnlockEvent
    let state: UnlockLadder.State
    let isWorn: Bool
    let onOpen: () -> Void

    static let width: CGFloat = 104

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 0) {
                picture
                Text(item.shape.title)
                    .font(.montserratBold(size: 11))
                    .foregroundStyle(state == .locked ? .white.opacity(0.62) : .white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 27, alignment: .center)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                Text(UnlockCopy.threshold(item, in: event))
                    .font(.montserratBold(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(state == .next ? Color.accent : .white.opacity(0.45))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.top, 3)
                    .padding(.bottom, 9)
            }
            .frame(width: Self.width)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UnlockStyle.tileFill))
            .overlay(alignment: .topTrailing) {
                if state == .earned {
                    EarnedSash()
                } else if state == .locked {
                    LockBadge()
                        .padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                if isWorn {
                    UnlockTag(text: "ON", fill: Color.accent, ink: UnlockStyle.limeInk)
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(border)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.shape.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows it on your athlete")
    }

    private var picture: some View {
        Image(item.shape.thumbnailName)
            .resizable()
            .scaledToFit()
            .frame(width: 74, height: 74)
            .shadow(color: .black.opacity(0.55), radius: 4, y: 6)
            .opacity(state == .locked ? 0.45 : 1)
            .saturation(state == .locked ? 0.5 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(
                RadialGradient(
                    colors: [UnlockStyle.pumpkin.opacity(state == .earned ? 0.32 : 0.12), .clear],
                    center: UnitPoint(x: 0.5, y: 0.55),
                    startRadius: 0,
                    endRadius: 46
                )
            )
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        switch state {
        case .earned: shape.strokeBorder(Color.accent.opacity(0.55), lineWidth: 1)
        case .next: shape.strokeBorder(Color.accent.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        case .locked: shape.strokeBorder(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var accessibilityValue: String {
        let rule = UnlockCopy.threshold(item, in: event)
        switch state {
        case .earned: return isWorn ? "Earned, on your athlete" : "Earned"
        case .next: return "Next, \(rule)"
        case .locked: return "Locked, \(rule)"
        }
    }
}

/// The lime band across an earned tile's top-right corner.
struct EarnedSash: View {
    var body: some View {
        Text("EARNED")
            .font(.montserratBold(size: 7.5))
            .tracking(0.8)
            .foregroundStyle(UnlockStyle.limeInk)
            .frame(width: 86, height: 15)
            .background(Color.accent)
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .rotationEffect(.degrees(45))
            .offset(x: 25, y: 11)
            .frame(width: 60, height: 40, alignment: .topTrailing)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A small capsule label on a tile's corner: ON, NEW.
struct UnlockTag: View {
    let text: String
    let fill: Color
    let ink: Color

    var body: some View {
        Text(text)
            .font(.montserratBold(size: 8))
            .tracking(0.8)
            .foregroundStyle(ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(fill))
            .accessibilityHidden(true)
    }
}

/// The small lock on an item not earned yet.
struct LockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 18, height: 18)
            .background(Circle().fill(.white.opacity(0.12)))
            .accessibilityHidden(true)
    }
}
