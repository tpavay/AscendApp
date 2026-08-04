import SwiftUI

/// The whole routine, above the strip you edit.
///
/// A ridge rather than blocks, because a path has no minimum width per interval and holds forty
/// as easily as five. Over it sits the window: the intervals the builder is drawing at full size
/// underneath. Drag it to change which ones those are - that is the whole interaction.
struct RoutineTimelineOverview: View {
    let intervals: [RoutineInterval]
    let visibleRange: Range<Int>
    /// Where the drag has carried the window's leading edge, as a fraction of the routine.
    let onScrub: (Double) -> Void
    /// VoiceOver cannot drag, so the window also steps one interval at a time.
    let onStep: (Int) -> Void
    /// The sheet must not read a scrub as a swipe to dismiss.
    let onScrubbingChange: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOriginFraction: Double?

    /// Tall enough to be a control in its own right, which is the whole point of the window.
    static let ridgeHeight: CGFloat = RoutineTimelineWindow.minimumTapTarget

    /// Seven short intervals inside a long routine cover very little of the ridge, and a hairline
    /// is not something a finger can find.
    private static let minimumWindowWidth: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("WHOLE ROUTINE")
                .font(.montserratSemiBold(size: 9))
                .tracking(0.8)
                .foregroundStyle(Color.customGray)
                .accessibilityHidden(true)

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ridge
                    window(availableWidth: proxy.size.width)
                }
                .contentShape(.rect)
                .highPriorityGesture(scrubGesture(availableWidth: proxy.size.width))
            }
            .frame(height: Self.ridgeHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RoutineIntervalVoiceOver.overviewLabel)
        .accessibilityValue(
            RoutineIntervalVoiceOver.overviewValue(visibleRange: visibleRange, count: intervals.count)
        )
        .accessibilityHint(RoutineIntervalVoiceOver.overviewHint)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onStep(1)
            case .decrement:
                onStep(-1)
            @unknown default:
                break
            }
        }
    }

    // MARK: - Ridge

    private var ridge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.03))

            // One filled path and one stroke, whatever the interval count - the overview is the
            // surface a forty-interval routine has to stay cheap on.
            RoutineRidgeShape(intervals: intervals, totalDuration: totalDuration)
                .fill(
                    LinearGradient(
                        colors: [routineColor.opacity(0.55), routineColor.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.top, 3)

            RoutineRidgeShape(intervals: intervals, totalDuration: totalDuration, strokeOnly: true)
                .stroke(routineColor.opacity(0.9), lineWidth: 1.4)
                .padding(.top, 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: - Window

    private func window(availableWidth: CGFloat) -> some View {
        let span = RoutineTimelineWindow.span(
            durations: intervals.map(\.duration),
            range: visibleRange
        )
        let width = max(availableWidth * (span.upperBound - span.lowerBound), Self.minimumWindowWidth)
        let offset = min(availableWidth * span.lowerBound, max(availableWidth - width, 0))

        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.accent.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.accent, lineWidth: 1.5)
            )
            .frame(width: width, height: Self.ridgeHeight)
            .offset(x: offset)
            .allowsHitTesting(false)
    }

    // MARK: - Gesture

    private func scrubGesture(availableWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard availableWidth > 0 else { return }

                let travelled = Double(value.translation.width / availableWidth)

                if dragOriginFraction == nil {
                    // The gesture only opens after a few points of travel. Discounting them
                    // means the window starts from where it already was rather than jumping.
                    dragOriginFraction = RoutineTimelineWindow.span(
                        durations: intervals.map(\.duration),
                        range: visibleRange
                    ).lowerBound - travelled
                    onScrubbingChange(true)
                }

                onScrub((dragOriginFraction ?? 0) + travelled)
            }
            .onEnded { _ in
                dragOriginFraction = nil
                onScrubbingChange(false)
            }
    }

    // MARK: - Derived

    private var totalDuration: TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }

    private var routineColor: Color {
        RoutineIntervalScale.averageColor(of: intervals, colorScheme: colorScheme)
    }
}

#Preview("Twenty intervals") {
    let intervals = (0..<20).map { index in
        RoutineInterval(duration: 120, intensityValue: index < 10 ? 5 + index * 2 : 23 - (index - 10) * 2, order: index)
    }

    return RoutineTimelineOverview(
        intervals: intervals,
        visibleRange: 6..<13,
        onScrub: { _ in },
        onStep: { _ in },
        onScrubbingChange: { _ in }
    )
    .padding(20)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
