import SwiftUI

struct AscendLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: reduceMotion
            )
        ) { context in
            let rotation = reduceMotion
                ? 0
                : context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.1) / 1.1 * 360

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(
                        Color.ascendAccent,
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(rotation))
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityLabel("Loading")
    }
}
