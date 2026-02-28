//
//  StatsCelebrationScreen.swift
//  AscendApp
//

import SwiftUI

/// Screen 1: Title, stat grid, and done button
struct StatsCelebrationScreen: View {
    var viewModel: ImportCelebrationViewModel
    let onDone: () -> Void
    var onSetGoal: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var stats: [ImportCelebrationViewModel.StatItem] {
        viewModel.visibleStats
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 14) {
                heroBadge

                Text(viewModel.titleText)
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)

                if let subtitle = viewModel.subtitleText {
                    Text(subtitle)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)
                }

                if viewModel.showGoalSection {
                    if let snapshot = viewModel.goalSnapshot {
                        goalProgressSection(snapshot)
                            .opacity(viewModel.goalSectionOpacity)
                    }
                }
            }
            .opacity(viewModel.titleOpacity)
            .padding(.horizontal, 28)

            Spacer()
                .frame(height: 30)

            // Stats grid — 2 columns
            let columns = [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ]

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(stats) { stat in
                    StatTile(
                        value: viewModel.currentValue(for: stat),
                        label: stat.label,
                        iconName: iconName(for: stat.type)
                    )
                    .opacity(viewModel.statOpacities[stat.type] ?? 0)
                }
            }
            .scaleEffect(viewModel.statGridScale)
            .padding(.horizontal, 24)

            Spacer(minLength: 28)

            if !viewModel.showGoalCompletionScreen {
                if shouldShowSetGoalActions {
                    VStack(spacing: 10) {
                        VStack(spacing: 2) {
                            Text("Don’t lose this momentum")
                                .font(.montserratSemiBold(size: 15))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                            Text("Turn this import into weekly progress.")
                                .font(.montserratRegular(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 6)

                        Button {
                            onSetGoal?()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "target")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Lock In My Weekly Goal")
                                    .font(.montserratSemiBold(size: 16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(.accent)
                            )
                        }

                        Button {
                            TelemetryManager.shared.log(.celebrationDismissed)
                            onDone()
                        } label: {
                            Text("Done for now")
                                .font(.montserratMedium(size: 14))
                                .foregroundStyle(
                                    effectiveColorScheme == .dark
                                        ? .white.opacity(0.74)
                                        : .black.opacity(0.65)
                                )
                        }
                    }
                    .opacity(viewModel.buttonOpacity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                } else {
                    // Done button
                    Button {
                        TelemetryManager.shared.log(.celebrationDismissed)
                        onDone()
                    } label: {
                        Text("Done")
                            .font(.montserratSemiBold(size: 17))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Capsule()
                                    .fill(.accent)
                            )
                    }
                    .opacity(viewModel.buttonOpacity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
        }
        .overlayPreferenceValue(HeroBadgeBoundsPreferenceKey.self) { heroAnchor in
            GeometryReader { proxy in
                let heroRect = heroAnchor.map { proxy[$0] }
                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)
                let topSafeInset = proxy.safeAreaInsets.top
                let center = UnitPoint(
                    x: (heroRect?.midX ?? width * 0.5) / width,
                    y: (heroRect?.midY ?? height * 0.18) / height
                )

                ZStack {
                    RadialGradient(
                        colors: [
                            .accent.opacity(viewModel.impactFlashOpacity),
                            .clear
                        ],
                        center: center,
                        startRadius: 24,
                        endRadius: 420
                    )
                    .ignoresSafeArea()
                    .blendMode(.screen)

                    if let heroRect {
                        let boltStart = CGPoint(x: width * 0.5, y: topSafeInset + 6)
                        let boltEnd = CGPoint(x: heroRect.midX, y: heroRect.midY)
                        let boltPath = lightningPath(from: boltStart, to: boltEnd)

                        boltPath
                            .trimmedPath(from: 0, to: min(max(viewModel.lightningProgress, 0), 1))
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.95),
                                        .accent.opacity(0.95)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                            )
                            .opacity(viewModel.lightningOpacity)
                            .blendMode(.plusLighter)
                            .shadow(color: .white.opacity(0.7), radius: 8)

                        ElectricBurstShape(spikes: 14, innerRatio: 0.46)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.9),
                                        .accent.opacity(0.95),
                                        .accent.opacity(0.45)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round)
                            )
                            .frame(
                                width: heroRect.width * viewModel.shockwavePrimaryScale,
                                height: heroRect.height * viewModel.shockwavePrimaryScale
                            )
                            .position(x: heroRect.midX, y: heroRect.midY)
                            .opacity(viewModel.shockwavePrimaryOpacity)
                            .blendMode(.plusLighter)
                            .shadow(color: .accent.opacity(0.8), radius: 12)

                        ElectricBurstShape(spikes: 10, innerRatio: 0.40)
                            .stroke(
                                .white.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                            )
                            .rotationEffect(.degrees(18))
                            .frame(
                                width: heroRect.width * viewModel.shockwaveSecondaryScale,
                                height: heroRect.height * viewModel.shockwaveSecondaryScale
                            )
                            .position(x: heroRect.midX, y: heroRect.midY)
                            .opacity(viewModel.shockwaveSecondaryOpacity)
                            .blendMode(.plusLighter)
                            .shadow(color: .white.opacity(0.65), radius: 9)
                    }

                    ScreenPerimeterShape(cornerRadius: 30)
                        .trim(
                            from: min(max(viewModel.perimeterSurgeTail, 0), 0.999),
                            to: max(min(viewModel.perimeterSurgeHead, 1), viewModel.perimeterSurgeTail + 0.001)
                        )
                        .stroke(
                            .accent.opacity(0.95),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                        .padding(8)
                        .opacity(viewModel.perimeterSurgeOpacity)
                        .blendMode(.plusLighter)
                        .shadow(color: .accent.opacity(0.9), radius: 8)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var heroBadge: some View {
        ZStack {
            Circle()
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.35) : .gray.opacity(0.12))
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(effectiveColorScheme == .dark ? 0.14 : 0.2), lineWidth: 1)
                )

            Circle()
                .stroke(.accent.opacity(0.35), lineWidth: 2)
                .frame(width: 72, height: 72)

            Image(systemName: "figure.stairs")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.accent)

            Circle()
                .fill(.accent)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                )
                .offset(x: 24, y: 24)
        }
        .scaleEffect(viewModel.heroScale)
        .anchorPreference(key: HeroBadgeBoundsPreferenceKey.self, value: .bounds) { $0 }
    }

    private func iconName(for type: ImportCelebrationViewModel.StatType) -> String {
        switch type {
        case .duration:
            return "stopwatch"
        case .steps:
            return "figure.stairs"
        case .floors:
            return "building.2"
        case .verticalClimb:
            return "arrow.up"
        }
    }

    private var shouldShowSetGoalActions: Bool {
        viewModel.goalSnapshot == nil && viewModel.showGoalSection
    }

    private func goalProgressSection(_ snapshot: GoalCelebrationSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Weekly Goal")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                Text("\(Int((viewModel.goalBarProgress * 100).rounded()))%")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.accent)
            }

            Text("\(snapshot.newCurrent.formatted()) / \(snapshot.target.formatted()) \(snapshot.metric.unit)")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.secondary)

            AnimatedGoalProgressBar(progress: viewModel.goalBarProgress)

            Text("Target: \(snapshot.formattedTarget)")
                .font(.montserratRegular(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func lightningPath(from start: CGPoint, to end: CGPoint) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y

        let p1 = CGPoint(x: start.x + (dx * 0.22) - 26, y: start.y + (dy * 0.24))
        let p2 = CGPoint(x: start.x + (dx * 0.46) + 20, y: start.y + (dy * 0.48))
        let p3 = CGPoint(x: start.x + (dx * 0.72) - 18, y: start.y + (dy * 0.74))

        var path = Path()
        path.move(to: start)
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.addLine(to: end)
        return path
    }

}

private struct ElectricBurstShape: Shape {
    let spikes: Int
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) * 0.5
        let innerRadius = outerRadius * innerRatio
        let count = max(spikes * 2, 6)

        var path = Path()
        for index in 0..<count {
            let angle = (Double(index) / Double(count)) * (.pi * 2) - (.pi / 2)
            let ripple = 0.85 + (0.15 * sin(Double(index) * 1.37))
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius * ripple
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()
        return path
    }
}

private struct ScreenPerimeterShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width * 0.5, rect.height * 0.5)
        let xMin = rect.minX
        let xMax = rect.maxX
        let yMin = rect.minY
        let yMax = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: yMin))
        path.addLine(to: CGPoint(x: xMax - radius, y: yMin))
        path.addArc(
            center: CGPoint(x: xMax - radius, y: yMin + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: xMax, y: yMax - radius))
        path.addArc(
            center: CGPoint(x: xMax - radius, y: yMax - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: xMin + radius, y: yMax))
        path.addArc(
            center: CGPoint(x: xMin + radius, y: yMax - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: xMin, y: yMin + radius))
        path.addArc(
            center: CGPoint(x: xMin + radius, y: yMin + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.midX, y: yMin))
        return path
    }
}

private struct HeroBadgeBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
