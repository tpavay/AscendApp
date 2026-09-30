import SwiftUI

/// One side of the count beyond the pack: "+193 AHEAD" under the step count, "+692 BEHIND"
/// above the stats.
struct AscendMountainCrowdChip: View {
    enum Side {
        case ahead
        case behind
    }

    let count: Int
    let side: Side

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: side == .ahead ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .heavy))
            Text("+\(count.formatted()) \(side == .ahead ? "AHEAD" : "BEHIND")")
                .font(.montserratBold(size: 11))
                .tracking(0.8)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background(Capsule(style: .continuous).fill(.black.opacity(0.5)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count.formatted()) more climbers \(side == .ahead ? "ahead" : "behind")")
    }
}
