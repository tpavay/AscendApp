import SwiftUI

/// The field a board ranks, named and counted, pinned beneath its rows.
///
/// A live race collapses a rival's repeat runs to their best while the static
/// per-climb board keeps every completion, so the two boards show different
/// totals for one climb on purpose. Both draw this one line, because the moment
/// the treatment differs the two totals stop reading as two deliberate answers.
struct LiveReplayFieldSizeLine: View {
    let field: LiveReplayFieldSize
    let effectiveColorScheme: ColorScheme

    var body: some View {
        Text(field.label)
            .font(.montserratBold(size: 10))
            .tracking(1.1)
            .foregroundStyle(secondaryColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(hairlineColor)
                    .frame(height: 1)
            }
    }

    private var secondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48)
    }

    private var hairlineColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }
}
