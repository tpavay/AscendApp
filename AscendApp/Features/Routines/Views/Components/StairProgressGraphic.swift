import SwiftUI

struct StairProgressGraphic: View {
    let progress: Double
    var glowColor: Color = .accent
    var stepCount: Int = 8
    var outlineColor: Color = .white.opacity(Metrics.baseOutlineOpacity)

    var body: some View {
        GeometryReader { geometry in
            let clampedProgress = min(max(progress, 0), 1)
            let resolvedStepCount = resolvedStepCount(in: geometry.size)
            let completedSteps = clampedProgress * Double(resolvedStepCount)
            let layout = resolvedLayout(in: geometry.size, stepCount: resolvedStepCount)

            ZStack(alignment: .bottomTrailing) {
                ForEach(0..<resolvedStepCount, id: \.self) { index in
                    let fillAmount = min(max(completedSteps - Double(index), 0), 1)

                    StairStep(
                        fillAmount: fillAmount,
                        glowColor: glowColor,
                        outlineColor: outlineColor
                    )
                    .frame(width: layout.width(for: index), height: layout.stepHeight)
                    .offset(
                        y: -CGFloat(index) * layout.verticalStride
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .animation(.linear(duration: Metrics.progressAnimationDuration), value: progress)
    }

    private func resolvedStepCount(in size: CGSize) -> Int {
        let heightDriven = Int((size.height / Metrics.targetVerticalStride).rounded(.down))
        let adaptiveCount = min(max(heightDriven, Metrics.minimumAdaptiveStepCount), Metrics.maximumAdaptiveStepCount)
        return max(stepCount, adaptiveCount)
    }

    private func resolvedLayout(in size: CGSize, stepCount: Int) -> StairLayout {
        let spanCount = CGFloat(max(stepCount - 1, 1))
        let bottomStepWidth = min(
            max(size.width * Metrics.bottomStepWidthRatio, Metrics.minimumBottomStepWidth),
            size.width
        )
        let topStepWidth = min(
            max(size.width * Metrics.topStepWidthRatio, Metrics.minimumTopStepWidth),
            bottomStepWidth
        )
        let stepHeight = min(
            max(size.height * Metrics.stepHeightRatio, Metrics.minimumStepHeight),
            Metrics.maximumStepHeight
        )
        let verticalStride = max((size.height - stepHeight) / spanCount, stepHeight + Metrics.minimumVerticalGap)

        return StairLayout(
            bottomStepWidth: bottomStepWidth,
            topStepWidth: topStepWidth,
            stepHeight: stepHeight,
            verticalStride: verticalStride,
            stepCount: stepCount
        )
    }
}

private struct StairStep: View {
    let fillAmount: Double
    let glowColor: Color
    let outlineColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: Metrics.pulseFrameInterval)) { context in
            let pulse = pulsePhase(at: context.date)
            let outlineProgress = min(max(fillAmount / Metrics.outlineLeadFraction, 0), 1)
            let visibleOutlineProgress = fillAmount > 0
                ? max(outlineProgress, Metrics.minimumVisibleOutlineProgress)
                : 0

            GeometryReader { geometry in
                let contentWidth = max(geometry.size.width - (Metrics.contentInset * 2), 0)
                let contentHeight = max(geometry.size.height - (Metrics.contentInset * 2), 0)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                        .fill(Color.jet.opacity(Metrics.baseFillOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                                .stroke(outlineColor, lineWidth: Metrics.baseOutlineWidth)
                        )

                    StepOutlineShape(cornerRadius: Metrics.cornerRadius)
                        .trim(from: 0, to: visibleOutlineProgress)
                        .stroke(
                            .white.opacity(Metrics.traceHighlightOpacity),
                            style: StrokeStyle(
                                lineWidth: Metrics.traceHighlightWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .opacity(fillAmount > 0 ? 1 : 0)

                    StepOutlineShape(cornerRadius: Metrics.cornerRadius)
                        .trim(from: 0, to: visibleOutlineProgress)
                        .stroke(
                            glowColor,
                            style: StrokeStyle(
                                lineWidth: Metrics.accentOutlineWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .opacity(outlineGlowOpacity)
                        .shadow(
                            color: glowColor.opacity(outlineGlowOpacity * Metrics.outlineGlowOpacity),
                            radius: Metrics.outlineGlowRadius,
                            x: 0,
                            y: 0
                        )
                        .animation(.linear(duration: Metrics.progressAnimationDuration), value: visibleOutlineProgress)

                    RoundedRectangle(cornerRadius: Metrics.fillCornerRadius)
                        .fill(glowColor)
                        .frame(width: max((contentWidth - (Metrics.fillInset * 2)) * interiorFillProgress, 0))
                        .frame(height: max(contentHeight - (Metrics.fillInset * 2), 0))
                        .opacity(activeFillOpacity(pulse: pulse))
                        .shadow(
                            color: glowColor.opacity(activeGlowOpacity(pulse: pulse)),
                            radius: activeGlowRadius(pulse: pulse),
                            x: 0,
                            y: 0
                        )
                        .padding(Metrics.fillInset)
                }
                .frame(width: contentWidth, height: contentHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var outlineGlowOpacity: Double {
        guard fillAmount > 0 else { return 0 }
        return Metrics.activeOutlineOpacity
    }

    private var interiorFillProgress: Double {
        let adjusted = (fillAmount - Metrics.outlineLeadFraction) / (1 - Metrics.outlineLeadFraction)
        return min(max(adjusted, 0), 1)
    }

    private var isActivelyFilling: Bool {
        interiorFillProgress > 0 && interiorFillProgress < 1
    }

    private func pulsePhase(at date: Date) -> Double {
        guard isActivelyFilling else { return 0 }
        let wave = sin(date.timeIntervalSinceReferenceDate * Metrics.pulseSpeed)
        return (wave + 1) * 0.5
    }

    private func activeFillOpacity(pulse: Double) -> Double {
        guard isActivelyFilling else { return interiorFillProgress > 0 ? 1 : 0 }
        return Metrics.minimumFillOpacity + (pulse * (1 - Metrics.minimumFillOpacity))
    }

    private func activeGlowOpacity(pulse: Double) -> Double {
        let base = interiorFillProgress > 0 ? Metrics.baseFillGlowOpacity : 0
        guard isActivelyFilling else { return base }
        return base + (pulse * Metrics.additionalPulseGlowOpacity)
    }

    private func activeGlowRadius(pulse: Double) -> CGFloat {
        guard isActivelyFilling else { return Metrics.baseFillGlowRadius }
        return Metrics.baseFillGlowRadius + (pulse * Metrics.additionalPulseGlowRadius)
    }
}

private struct StairLayout {
    let bottomStepWidth: CGFloat
    let topStepWidth: CGFloat
    let stepHeight: CGFloat
    let verticalStride: CGFloat
    let stepCount: Int

    func width(for index: Int) -> CGFloat {
        let spanCount = CGFloat(max(stepCount - 1, 1))
        let fraction = CGFloat(index) / spanCount
        return bottomStepWidth - ((bottomStepWidth - topStepWidth) * fraction)
    }
}

private struct StepOutlineShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        return path
    }
}

private enum Metrics {
    static let bottomStepWidthRatio: CGFloat = 0.94
    static let topStepWidthRatio: CGFloat = 0.52
    static let minimumBottomStepWidth: CGFloat = 156
    static let minimumTopStepWidth: CGFloat = 92
    static let stepHeightRatio: CGFloat = 0.115
    static let minimumStepHeight: CGFloat = 42
    static let maximumStepHeight: CGFloat = 64
    static let targetVerticalStride: CGFloat = 62
    static let minimumAdaptiveStepCount = 7
    static let maximumAdaptiveStepCount = 9
    static let minimumVerticalGap: CGFloat = 8

    static let cornerRadius: CGFloat = 8
    static let fillCornerRadius: CGFloat = 5
    static let fillInset: CGFloat = 5
    static let contentInset: CGFloat = 5
    static let baseFillOpacity = 0.92
    static let baseOutlineOpacity = 0.28
    static let baseOutlineWidth: CGFloat = 2
    static let accentOutlineWidth: CGFloat = 2.4
    static let traceHighlightWidth: CGFloat = 1.6
    static let outlineLeadFraction = 0.26
    static let minimumVisibleOutlineProgress = 0.14
    static let traceHighlightOpacity = 0.95
    static let activeOutlineOpacity = 1.0
    static let outlineGlowOpacity = 0.95
    static let outlineGlowRadius: CGFloat = 22

    static let baseFillGlowOpacity = 0.72
    static let additionalPulseGlowOpacity = 0.22
    static let baseFillGlowRadius: CGFloat = 16
    static let additionalPulseGlowRadius: CGFloat = 6
    static let minimumFillOpacity = 0.84

    static let pulseSpeed = 6.5
    static let pulseFrameInterval = 1.0 / 30.0
    static let progressAnimationDuration = 0.18
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        StairProgressGraphic(progress: 0.42)
            .frame(width: 260, height: 340)
            .padding(20)
    }
}
