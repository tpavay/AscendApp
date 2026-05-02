//
//  StatsCelebrationScreen.swift
//  AscendApp
//

import SwiftUI

/// Screen 1: Title, stat grid, and done button
struct StatsCelebrationScreen: View {
    var viewModel: ImportCelebrationViewModel
    let onDone: () -> Void

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

}
