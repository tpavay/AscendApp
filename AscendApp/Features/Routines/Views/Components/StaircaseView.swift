import SwiftUI

struct StaircaseView: View {
    let totalSteps: Int
    let currentStepIndex: Int
    let isWorkoutComplete: Bool
    var glowColor: Color = .accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: Metrics.timelineFrameInterval)) { context in
            GeometryReader { geometry in
                let stepFrames = makeStepFrames(in: geometry.size)
                let activeIndex = min(max(currentStepIndex, 0), max(stepFrames.count - 1, 0))
                let pulse = pulsePhase(at: context.date)
                let sheen = sheenPhase(at: context.date)

                ZStack(alignment: .bottomTrailing) {
                    staircaseTrace(for: stepFrames)
                        .stroke(
                            .white.opacity(Metrics.unfilledTraceOpacity),
                            style: StrokeStyle(lineWidth: Metrics.unfilledTraceLineWidth, lineCap: .round, lineJoin: .round)
                        )

                    filledTrace(for: stepFrames, through: activeIndex)
                        .stroke(
                            glowColor.opacity(Metrics.filledTraceOpacity),
                            style: StrokeStyle(lineWidth: Metrics.filledTraceLineWidth, lineCap: .round, lineJoin: .round)
                        )

                    ForEach(stepFrames) { step in
                        StaircaseStepCell(
                            step: step,
                            state: stepState(for: step.index, activeIndex: activeIndex),
                            glowColor: glowColor,
                            opacity: stepOpacity(for: step.index, activeIndex: activeIndex, pulse: pulse),
                            sheenProgress: step.index == activeIndex ? sheen : nil
                        )
                    }

                    if let activeStep = stepFrames[safe: activeIndex] {
                        Circle()
                            .fill(glowColor.opacity(Metrics.currentDotOpacity))
                            .frame(width: Metrics.currentDotDiameter, height: Metrics.currentDotDiameter)
                            .scaleEffect(reduceMotion ? 1 : Metrics.currentDotBaseScale + (pulse * Metrics.currentDotScaleRange))
                            .position(
                                x: activeStep.frame.minX,
                                y: activeStep.frame.minY
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .accessibilityHidden(true)
    }

    private func makeStepFrames(in size: CGSize) -> [StaircaseStepFrame] {
        guard totalSteps > 0, size.width > 0, size.height > 0 else { return [] }

        let nominalHeights = interpolatedValues(
            count: totalSteps,
            from: Metrics.maxStepHeight,
            to: Metrics.minStepHeight
        )
        let requiredGapHeight = CGFloat(max(totalSteps - 1, 0)) * Metrics.minimumStepGap
        let availableHeightForSteps = max(size.height - requiredGapHeight, 1)
        let heightScale = min(1, availableHeightForSteps / nominalHeights.reduce(0, +))
        let heights = nominalHeights.map { max($0 * heightScale, Metrics.minimumCompressedStepHeight) }

        let totalHeights = heights.reduce(0, +)
        let stepGap = totalSteps > 1
            ? max((size.height - totalHeights) / CGFloat(totalSteps - 1), Metrics.minimumStepGap)
            : 0

        let bottomWidth = min(size.width, Metrics.maxBottomWidth)
        let topWidth = min(bottomWidth, max(Metrics.minTopWidth, size.width * Metrics.minimumTopWidthRatio))
        let widths = interpolatedValues(
            count: totalSteps,
            from: bottomWidth,
            to: topWidth
        )

        var nextBottomEdge = size.height
        return (0..<totalSteps).map { index in
            let height = heights[index]
            let width = widths[index]
            let y = nextBottomEdge - height
            let x = size.width - width
            let progress = totalSteps > 1 ? CGFloat(index) / CGFloat(totalSteps - 1) : 0
            let frame = CGRect(x: x, y: y, width: width, height: height)
            nextBottomEdge = y - stepGap

            return StaircaseStepFrame(index: index, progress: progress, frame: frame)
        }
    }

    private func interpolatedValues(count: Int, from start: CGFloat, to end: CGFloat) -> [CGFloat] {
        guard count > 1 else { return [start] }

        return (0..<count).map { index in
            let fraction = CGFloat(index) / CGFloat(count - 1)
            return start + ((end - start) * fraction)
        }
    }

    private func stepState(for stepIndex: Int, activeIndex: Int) -> StaircaseStepState {
        if isWorkoutComplete || stepIndex < activeIndex {
            return .completed
        }

        if stepIndex == activeIndex {
            return .active
        }

        return .upcoming
    }

    private func stepOpacity(for stepIndex: Int, activeIndex: Int, pulse: Double) -> Double {
        if isWorkoutComplete {
            return completedOpacity(for: stepIndex, completedCount: max(totalSteps, 1))
        }

        if stepIndex < activeIndex {
            return completedOpacity(for: stepIndex, completedCount: max(activeIndex, 1))
        }

        if stepIndex == activeIndex {
            let animatedRange = reduceMotion ? 0 : Metrics.activePulseRange
            return Metrics.activeBaseOpacity + (pulse * animatedRange)
        }

        return 1
    }

    private func completedOpacity(for stepIndex: Int, completedCount: Int) -> Double {
        guard completedCount > 1 else { return Metrics.singleCompletedOpacity }
        let fraction = Double(stepIndex) / Double(completedCount - 1)
        return Metrics.completedOpacityBase + (Metrics.completedOpacityRange * fraction)
    }

    private func staircaseTrace(for steps: [StaircaseStepFrame]) -> Path {
        makeTracePath(for: steps, through: steps.count - 1)
    }

    private func filledTrace(for steps: [StaircaseStepFrame], through activeIndex: Int) -> Path {
        makeTracePath(for: steps, through: activeIndex)
    }

    private func makeTracePath(for steps: [StaircaseStepFrame], through lastIndex: Int) -> Path {
        guard !steps.isEmpty, lastIndex >= 0 else { return Path() }

        let cappedIndex = min(lastIndex, steps.count - 1)
        var path = Path()

        for index in 0...cappedIndex {
            let step = steps[index]

            if index == 0 {
                path.move(to: CGPoint(x: step.frame.minX, y: step.frame.maxY))
            }

            path.addLine(to: CGPoint(x: step.frame.minX, y: step.frame.minY))

            if index < cappedIndex, let nextStep = steps[safe: index + 1] {
                path.addLine(to: CGPoint(x: nextStep.frame.minX, y: nextStep.frame.maxY))
            }
        }

        return path
    }

    private func pulsePhase(at date: Date) -> Double {
        guard !reduceMotion else { return 0 }
        let wave = sin(date.timeIntervalSinceReferenceDate * Metrics.pulseSpeed)
        return (wave + 1) * 0.5
    }

    private func sheenPhase(at date: Date) -> CGFloat {
        guard !reduceMotion else { return 0.5 }

        let cycleDuration = Metrics.sheenDuration + Metrics.sheenResetHoldDuration
        let cycle = date.timeIntervalSinceReferenceDate.remainder(dividingBy: cycleDuration)

        guard cycle < Metrics.sheenDuration else {
            return 1 + Metrics.activeSheenOverscanProgress
        }

        let normalized = CGFloat(cycle / Metrics.sheenDuration)
        let travelRange = 1 + (Metrics.activeSheenOverscanProgress * 2)
        return -Metrics.activeSheenOverscanProgress + (normalized * travelRange)
    }
}

private struct StaircaseStepCell: View {
    let step: StaircaseStepFrame
    let state: StaircaseStepState
    let glowColor: Color
    let opacity: Double
    let sheenProgress: CGFloat?

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [
                glowColor.opacity(0.94),
                glowColor.darker(by: 0.18).opacity(0.82)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.white.opacity(Metrics.upcomingFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(Metrics.upcomingBorderOpacity), lineWidth: Metrics.upcomingBorderWidth)
                )

            if state != .upcoming {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fillGradient)
                    .opacity(opacity)

                if let sheenProgress, state == .active {
                    sheenOverlay(progress: sheenProgress)
                }

                Rectangle()
                    .fill(.white.opacity(state == .active ? Metrics.activeTopHighlightOpacity : Metrics.completedTopHighlightOpacity))
                    .frame(height: 1)
                    .padding(.horizontal, 1.5)
            }
        }
        .frame(width: step.frame.width, height: step.frame.height)
        .position(x: step.frame.midX, y: step.frame.midY)
    }

    private var cornerRadius: CGFloat {
        max(Metrics.maxCornerRadius - (step.progress * Metrics.cornerRadiusRange), Metrics.minCornerRadius)
    }

    @ViewBuilder
    private func sheenOverlay(progress: CGFloat) -> some View {
        let bandWidth = max(step.frame.width * Metrics.activeSheenWidthRatio, Metrics.activeSheenMinimumWidth)
        let overscan = bandWidth * Metrics.activeSheenOverscanFactor
        let travelDistance = step.frame.width + (bandWidth * 2) + (overscan * 2)
        let xOffset = (-bandWidth - overscan) + (travelDistance * progress)

        Color.clear
            .frame(width: step.frame.width, height: step.frame.height)
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [
                        .white.opacity(0),
                        .white.opacity(Metrics.activeSheenPeakOpacity * 0.45),
                        .white.opacity(Metrics.activeSheenPeakOpacity),
                        .white.opacity(Metrics.activeSheenPeakOpacity * 0.45),
                        .white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bandWidth, height: step.frame.height)
                .offset(x: xOffset)
            }
            .blendMode(.screen)
            .mask(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .frame(width: step.frame.width, height: step.frame.height)
            )
    }
}

private struct StaircaseStepFrame: Identifiable {
    let index: Int
    let progress: CGFloat
    let frame: CGRect

    var id: Int { index }
}

private enum StaircaseStepState {
    case upcoming
    case completed
    case active
}

private enum Metrics {
    static let maxBottomWidth: CGFloat = 265
    static let minTopWidth: CGFloat = 13
    static let minimumTopWidthRatio: CGFloat = 0.05

    static let maxStepHeight: CGFloat = 42
    static let minStepHeight: CGFloat = 20
    static let minimumCompressedStepHeight: CGFloat = 12
    static let minimumStepGap: CGFloat = 1

    static let maxCornerRadius: CGFloat = 8
    static let minCornerRadius: CGFloat = 4
    static let cornerRadiusRange: CGFloat = 4

    static let upcomingFillOpacity = 0.02
    static let upcomingBorderOpacity = 0.08
    static let upcomingBorderWidth: CGFloat = 1

    static let completedOpacityBase = 0.3
    static let completedOpacityRange = 0.6
    static let singleCompletedOpacity = 0.9

    static let activeBaseOpacity = 0.88
    static let activePulseRange = 0.04
    static let activeTopHighlightOpacity = 0.15
    static let completedTopHighlightOpacity = 0.05

    static let unfilledTraceOpacity = 0.08
    static let unfilledTraceLineWidth: CGFloat = 1
    static let filledTraceOpacity = 0.25
    static let filledTraceLineWidth: CGFloat = 1.5
    static let currentDotDiameter: CGFloat = 6
    static let currentDotOpacity = 0.6
    static let currentDotBaseScale = 0.92
    static let currentDotScaleRange = 0.18

    static let pulseSpeed = 3.2
    static let sheenDuration = 2.4
    static let sheenResetHoldDuration = 0.24
    static let activeSheenPeakOpacity = 0.22
    static let activeSheenWidthRatio: CGFloat = 0.42
    static let activeSheenMinimumWidth: CGFloat = 56
    static let activeSheenOverscanFactor: CGFloat = 0.75
    static let activeSheenOverscanProgress: CGFloat = 0.26
    static let timelineFrameInterval = 1.0 / 24.0
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        StaircaseView(
            totalSteps: 9,
            currentStepIndex: 3,
            isWorkoutComplete: false
        )
        .frame(width: 300, height: 430)
        .padding()
    }
}
