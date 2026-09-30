import SwiftUI

/// The Mountain's standing, top right: where the climber stands, worded exactly as the Lock
/// Screen words it, and the way into who they race.
///
/// It counts everyone on the board whoever is on the stairs - settled by the captain on
/// 2026-09-29 - so the number never changes meaning when the field is narrowed.
struct AscendMountainRacePill: View {
    let standing: LiveClimbStandingText
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(label)
                    .font(.montserratBold(size: 13))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accent)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .background(Capsule(style: .continuous).fill(.black.opacity(0.55)))
            .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Opens who you race.")
    }

    private var label: String {
        standing.detailLabel ?? standing.secondaryLabel ?? standing.caption
    }
}
