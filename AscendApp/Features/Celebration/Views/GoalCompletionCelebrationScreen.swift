//
//  GoalCompletionCelebrationScreen.swift
//  AscendApp
//

import SwiftUI

struct GoalCompletionCelebrationScreen: View {
    let data: ImportCelebrationData
    let buttonOpacity: Double
    let onDone: () -> Void

    @State private var hasStarted = false
    @State private var chainProgress: CGFloat = 0
    @State private var chainGlowOpacity: Double = 0
    @State private var badgeScale: CGFloat = 0.72
    @State private var badgeGlowOpacity: Double = 0
    @State private var firstLineOpacity: Double = 0
    @State private var firstLineOffset: CGFloat = 18
    @State private var secondLineOpacity: Double = 0
    @State private var secondLineOffset: CGFloat = 24
    @State private var kickerOpacity: Double = 0
    @State private var shakePhase: CGFloat = 0
    @State private var shakeAmplitude: CGFloat = 0
    @State private var animatedMetricValues: [GoalCompletionMetric.Kind: Int] = [:]
    @State private var metricOpacities: [GoalCompletionMetric.Kind: Double] = [:]

    private var snapshot: GoalCelebrationSnapshot? {
        data.goalSnapshot
    }

    private var completionContext: GoalCompletionContext {
        snapshot?.completionContext ?? fallbackContext
    }

    private var message: GoalCompletionMessage {
        completionContext.message
    }

    private var supportingMetrics: [GoalCompletionMetric] {
        completionContext.supportingMetrics
    }

    private var goalBadgeIcon: String {
        snapshot?.metric.icon ?? "figure.stairs"
    }

    private var fallbackContext: GoalCompletionContext {
        let metrics: [GoalCompletionMetric] = [
            GoalCompletionMetric(
                kind: .workouts,
                iconName: "figure.run",
                value: max(data.importedCount, 1),
                label: data.importedCount == 1 ? "workout" : "workouts"
            ),
            GoalCompletionMetric(
                kind: .duration,
                iconName: "stopwatch",
                value: max(Int(data.totalDuration / 60), 1),
                label: "minutes"
            ),
            GoalCompletionMetric(
                kind: .steps,
                iconName: "figure.stairs",
                value: max(data.totalSteps, 1),
                label: "steps"
            )
        ]

        return GoalCompletionContext(
            message: GoalCompletionMessage(
                kicker: "GOAL COMPLETED",
                line1: "You showed up,",
                line2: "and finished strong."
            ),
            supportingMetrics: metrics
        )
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    .accent.opacity(0.28),
                    .accent.opacity(0.08),
                    .black
                ],
                center: .center,
                startRadius: 10,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 44)

                Text(message.kicker)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.accent)
                    .tracking(2.0)
                    .opacity(kickerOpacity)

                goalBadge
                    .scaleEffect(badgeScale)
                    .overlay(
                        Circle()
                            .fill(.accent.opacity(0.2 * badgeGlowOpacity))
                            .frame(width: 160, height: 160)
                            .blur(radius: 24)
                    )

                driveBar
                    .frame(height: 24)
                    .padding(.horizontal, 28)

                HStack(spacing: 10) {
                    ForEach(supportingMetrics) { metric in
                        metricTile(
                            icon: metric.iconName,
                            value: animatedMetricValues[metric.kind] ?? 0,
                            label: metric.label,
                            opacity: metricOpacities[metric.kind] ?? 0
                        )
                    }
                }
                .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    Text(message.line1)
                        .font(.montserratSemiBold(size: 23))
                        .foregroundStyle(.white.opacity(0.95))
                        .opacity(firstLineOpacity)
                        .offset(y: firstLineOffset)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    Text(message.line2)
                        .font(.montserratBold(size: 50))
                        .foregroundStyle(.white)
                        .opacity(secondLineOpacity)
                        .offset(y: secondLineOffset)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 10)

                Spacer()

                Button {
                    TelemetryManager.shared.log(.celebrationDismissed)
                    onDone()
                } label: {
                    Text("Own This Win")
                        .font(.montserratSemiBold(size: 17))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(.accent)
                        )
                }
                .opacity(buttonOpacity)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .modifier(ScreenShakeEffect(phase: shakePhase, amplitude: shakeAmplitude))
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            initializeMetricAnimationState()
            await runSequence()
        }
    }

    private var goalBadge: some View {
        ZStack {
            Circle()
                .fill(.jetLighter.opacity(0.42))
                .frame(width: 92, height: 92)
                .overlay(
                    Circle()
                        .stroke(.accent.opacity(0.34), lineWidth: 2)
                )

            Image(systemName: goalBadgeIcon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.accent)

            Circle()
                .fill(.accent)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                )
                .offset(x: 30, y: 30)
        }
    }

    private var driveBar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(height: 10)

                Capsule()
                    .fill(.accent)
                    .frame(width: max(10, width * chainProgress), height: 10)

                Capsule()
                    .fill(.white.opacity(0.65))
                    .frame(width: 48, height: 10)
                    .blur(radius: 6)
                    .offset(x: max(0, (width * chainProgress) - 24))
                    .opacity(chainGlowOpacity)

                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in
                        Rectangle()
                            .fill(.black.opacity(0.35))
                            .frame(width: 2)
                        Spacer()
                    }
                }
                .padding(.horizontal, 4)
                .frame(height: 10)
            }
        }
    }

    private func metricTile(icon: String, value: Int, label: String, opacity: Double) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.accent)
            Text(value.formatted())
                .font(.montserratBold(size: 34))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.jetLighter.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .opacity(opacity)
    }

    private func initializeMetricAnimationState() {
        for metric in supportingMetrics {
            animatedMetricValues[metric.kind] = 0
            metricOpacities[metric.kind] = 0
        }
    }

    @MainActor
    private func runSequence() async {
        let haptics = HapticsManager.shared

        withAnimation(.easeOut(duration: 0.12)) {
            kickerOpacity = 1
        }

        withAnimation(.spring(response: 0.36, dampingFraction: 0.62)) {
            badgeScale = 1.0
            badgeGlowOpacity = 1.0
        }
        haptics.trigger(.mediumImpact)
        try? await Task.sleep(for: .milliseconds(120))

        withAnimation(.easeInOut(duration: 0.58)) {
            chainProgress = 1
            chainGlowOpacity = 1
        }
        await animateDrivePulseHaptics(haptics: haptics)

        try? await Task.sleep(for: .milliseconds(120))
        for (index, metric) in supportingMetrics.enumerated() {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.76)) {
                metricOpacities[metric.kind] = 1
            }

            await animateCounter(
                to: metric.value,
                duration: 0.42 + (Double(index) * 0.08),
                assign: { animatedMetricValues[metric.kind] = $0 },
                haptics: haptics
            )
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.74)) {
            firstLineOpacity = 1
            firstLineOffset = 0
        }

        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.spring(response: 0.44, dampingFraction: 0.68)) {
            secondLineOpacity = 1
            secondLineOffset = 0
        }

        withAnimation(.linear(duration: 0.4)) {
            shakePhase = 4.0
        }
        withAnimation(.easeIn(duration: 0.06)) {
            shakeAmplitude = 13
        }

        await haptics.goalCompletionBurst()

        withAnimation(.easeOut(duration: 0.2)) {
            shakeAmplitude = 0
            chainGlowOpacity = 0.72
            badgeGlowOpacity = 0.86
        }
    }

    @MainActor
    private func animateCounter(
        to target: Int,
        duration: Double,
        assign: (Int) -> Void,
        haptics: HapticsManager
    ) async {
        let clampedTarget = max(target, 1)
        let tickCount = min(34, max(10, Int(ceil(Double(clampedTarget) / 120.0))))
        let step = max(1, Int(ceil(Double(clampedTarget) / Double(tickCount))))
        let intervalMs = max(14, Int((duration / Double(max(tickCount, 1))) * 1000))

        var current = 0
        for index in 0..<tickCount {
            current = min(clampedTarget, current + step)
            assign(current)

            haptics.trigger(.lightImpact)

            if index < tickCount - 1 {
                try? await Task.sleep(for: .milliseconds(intervalMs))
            }
        }

        assign(clampedTarget)
        haptics.trigger(.heavyImpact)
    }

    @MainActor
    private func animateDrivePulseHaptics(haptics: HapticsManager) async {
        let pulses = 8
        for index in 0..<pulses {
            let progress = Double(index) / Double(max(pulses - 1, 1))
            haptics.triggerTraceSweep(progress: progress)
            if index < pulses - 1 {
                try? await Task.sleep(for: .milliseconds(72))
            }
        }
    }
}

private struct ScreenShakeEffect: GeometryEffect {
    var phase: CGFloat
    var amplitude: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(phase, amplitude) }
        set {
            phase = newValue.first
            amplitude = newValue.second
        }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        let x = sin(phase * .pi * 8) * amplitude
        let y = sin(phase * .pi * 13) * (amplitude * 0.38)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}
