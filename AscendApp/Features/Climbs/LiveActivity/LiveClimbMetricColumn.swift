import SwiftUI

/// One labelled measurement on the Lock Screen and the expanded Dynamic Island.
///
/// Compiled into the app as well as the widget extension so the row it sits in
/// can be hosted by a test: the standing column changes height by state, and
/// whether its title stays level with `Steps` and `Time` is a fact read off the
/// screen, not off the source.
struct LiveClimbMetricColumn: View {
    let title: String
    /// Nil where the column has nothing to state and `secondary` carries the
    /// statement alone. A value that could not be resolved is `--`, never nil.
    let value: String?
    /// A second measurement of a different population, stated beneath the first
    /// rather than beside it - the same order the in-app panel puts them in.
    var secondary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)

            if let value {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if let secondary {
                Text(secondary)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
