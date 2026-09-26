import SwiftUI

/// The climber's previous best on this climb, drawn inside their own live row.
///
/// Locked with the captain on 2026-09-01 across `ghost-row-design-v2`,
/// `ghost-marker-line-geometry` and `marker-label-fade-and-ordinal-accent`, and
/// amended on 2026-09-26 (`best-label-orientation`). Five properties are the
/// design, not styling:
///
/// - **It is not a leaderboard row.** No rank cell, not tappable, never counted
///   in the rank or the field size. The completion it stands for is withdrawn
///   from the rows the window renders (captain, 2026-09-22; see
///   `LiveReplayLeaderboardWindow.locallyRankedRows`), so this position inside
///   the live row is its only representation.
/// - **It is a single line, never a two-sided box.** The progress fill passes one
///   edge cleanly instead of straddling a box through an ambiguous half-passed
///   state. The line sits to the *left* of the word.
/// - **It never draws over its host's content.** On a leaderboard row the line
///   passes behind the rank, avatar, name, `YOU` chip and step count, and the
///   word reads as a horizontal flag in the row's top margin (`.flag`). The
///   2026-09-01 treatment - the word in vertical letters beside the line - cut
///   through the climber's name on production, and on an open Just Climb the
///   name is where the marker usually lands; a vertical word that avoided the
///   name would have been withheld nearly everywhere. The Just Me summit bar has
///   no content inside it and keeps the vertical word (`.vertical`).
/// - **It carries no numbers.** No step count, no time, no "steps to catch
///   yourself". The visible distance between the fill's edge and the line is the
///   entire message.
/// - **The line never changes.** It does not darken, tint or fade once the fill
///   sweeps past it: which side the fill sits on is already the whole signal.
///   Only the *word* fades, and only where it would touch content or run out of
///   room.
struct LiveReplayPreviousBestMarker: View {
    enum LabelStyle {
        /// `BEST` in vertical letters, centred on the line's height.
        case vertical
        /// `BEST` reading horizontally along the top of the line.
        case flag
    }

    /// Where the previous best had reached, as a fraction of the same progress
    /// scale the row's own fill is drawn against.
    let progress: Double
    var labelStyle: LabelStyle = .vertical
    /// How much room the host's trailing number needs, where that number is not
    /// passed as an obstacle. The word fades out inside this margin; the line
    /// still travels through it.
    var trailingNumberInset: CGFloat = 0
    /// The host's content, in the marker's own coordinate space. The line passes
    /// behind each of these and the word is withheld wherever it would touch one
    /// (`LiveReplayPreviousBestMarkerLayout`).
    var obstacles: [CGRect] = []
    var lineWidth: CGFloat = 2
    var lineColor: Color = .white

    @State private var labelSize: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let layout = LiveReplayPreviousBestMarkerLayout(
                size: proxy.size,
                progress: progress,
                lineWidth: lineWidth,
                labelSize: labelSize,
                labelPlacement: labelStyle == .flag ? .top : .centered,
                obstacles: obstacles,
                trailingInset: trailingNumberInset
            )

            ZStack(alignment: .topLeading) {
                Color.clear

                LiveReplayPreviousBestLine(
                    centerX: layout.lineCenterX,
                    width: lineWidth,
                    segments: layout.lineSegments
                )
                .fill(lineColor)

                label
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self, of: \.size) { labelSize = $0 }
                    .offset(x: layout.labelFrame.minX, y: layout.labelFrame.minY)
                    .opacity(layout.showsLabel ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: layout.showsLabel)
            }
            .shadow(color: .black.opacity(0.55), radius: 2)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: layout.lineCenterX)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var label: some View {
        switch labelStyle {
        case .flag:
            Text("BEST")
                .font(.montserratBold(size: 8))
                .tracking(0.8)
                .foregroundStyle(lineColor.opacity(0.92))
        case .vertical:
            VStack(spacing: -1) {
                ForEach(Array("BEST".enumerated()), id: \.offset) { letter in
                    Text(String(letter.element))
                        .font(.montserratBold(size: 8))
                        .foregroundStyle(lineColor.opacity(0.92))
                }
            }
        }
    }
}

/// The marker's one line: a vertical rule at `centerX`, drawn only over
/// `segments`, so it can pass behind a row's content without touching it.
private struct LiveReplayPreviousBestLine: Shape {
    var centerX: CGFloat
    let width: CGFloat
    let segments: [ClosedRange<CGFloat>]

    var animatableData: CGFloat {
        get { centerX }
        set { centerX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            for segment in segments {
                path.addRect(
                    CGRect(
                        x: centerX - width / 2,
                        y: segment.lowerBound,
                        width: width,
                        height: segment.upperBound - segment.lowerBound
                    )
                )
            }
        }
    }
}
