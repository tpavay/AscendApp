import SwiftUI

/// One value over its caption in a compact Dynamic Island slot.
///
/// The leading and trailing slots are laid out by the system independently and
/// each centred in its own region, so a slot that draws one line instead of two
/// sits centred rather than pulling a neighbour out of line - there is no shared
/// row here to keep level.
struct LiveClimbCompactMetricView: View {
    /// Nil where the metric has nothing to state, which is not the same as a
    /// value that could not be resolved: that one arrives as `--`.
    let value: String?
    let label: String

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if let value {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(label)
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            } else {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(.white)
    }
}
