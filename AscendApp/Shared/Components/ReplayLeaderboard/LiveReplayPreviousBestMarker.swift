import SwiftUI

/// The climber's previous best on this climb, drawn inside their own live row.
///
/// Locked with the captain on 2026-09-01 across `ghost-row-design-v2`,
/// `ghost-marker-line-geometry` and `marker-label-fade-and-ordinal-accent`. Four
/// properties are the design, not styling:
///
/// - **It is not a row.** No rank cell, not tappable, never counted in the rank
///   or the field size. The withdrawal happens upstream, in
///   `LiveReplayLeaderboardWindow.opponentRows`; by the time the board renders,
///   the previous best exists only as this position.
/// - **It is a single line, never a two-sided box.** The progress fill passes one
///   edge cleanly instead of straddling a box through an ambiguous half-passed
///   state. The line sits to the *left* of the word, which reads in vertical
///   letters immediately to its right.
/// - **It carries no numbers.** No step count, no time, no "steps to catch
///   yourself". The visible distance between the fill's edge and the line is the
///   entire message.
/// - **The line never changes.** It does not darken, tint or fade once the fill
///   sweeps past it: which side the fill sits on is already the whole signal.
///   Only the *word* fades, and only where it would collide with the row's
///   trailing step count.
struct LiveReplayPreviousBestMarker: View {
    /// Where the previous best had reached, as a fraction of the same progress
    /// scale the row's own fill is drawn against.
    let progress: Double
    /// How much room the row's trailing step count needs. The word fades out
    /// inside this margin; the line still travels through it.
    var trailingNumberInset: CGFloat = 74
    var lineWidth: CGFloat = 2
    var lineColor: Color = .white

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let markerX = width * min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Color.clear

                HStack(alignment: .center, spacing: 3) {
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: lineWidth)

                    verticalLabel
                        .opacity(showsLabel(markerX: markerX, width: width) ? 1 : 0)
                        .animation(
                            .easeInOut(duration: 0.3),
                            value: showsLabel(markerX: markerX, width: width)
                        )
                }
                .fixedSize(horizontal: true, vertical: false)
                .shadow(color: .black.opacity(0.55), radius: 2)
                .offset(x: max(markerX - lineWidth / 2, 0))
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: markerX)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// `BEST` in vertical letters, reading top to bottom immediately right of the
    /// line.
    private var verticalLabel: some View {
        VStack(spacing: -1) {
            ForEach(Array("BEST".enumerated()), id: \.offset) { letter in
                Text(String(letter.element))
                    .font(.montserratBold(size: 8))
                    .foregroundStyle(lineColor.opacity(0.92))
            }
        }
    }

    private func showsLabel(markerX: CGFloat, width: CGFloat) -> Bool {
        width - markerX >= trailingNumberInset
    }
}
