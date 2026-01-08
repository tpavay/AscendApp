//
//  FitnessLevelSelectionView.swift
//  AscendApp
//
//  Settings view for changing fitness level.
//  Affects initial scoring thresholds for new users (first 10 workouts).
//

import SwiftUI

struct FitnessLevelSelectionView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)

                // Fitness Level Options
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Text("Fitness Level")
                            .font(.montserratSemiBold(size: 20))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                        Spacer()
                    }

                    VStack(spacing: 12) {
                        ForEach(FitnessLevel.allCases) { level in
                            fitnessLevelRow(level: level)
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)

                // Info section
                infoSection
                    .padding(.horizontal, 20)

                Spacer(minLength: 40)
            }
        }
        .themedBackground()
        .navigationTitle("Fitness Level")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }

    // MARK: - Fitness Level Row

    private func fitnessLevelRow(level: FitnessLevel) -> some View {
        Button(action: {
            settingsManager.setFitnessLevel(level)
        }) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: level.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.accent)
                }

                // Text Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.montserratSemiBold)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Text(level.description)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                        .lineLimit(2)
                }

                Spacer()

                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if settingsManager.fitnessLevel == level {
                        Circle()
                            .fill(.accent)
                            .frame(width: 16, height: 16)
                            .scaleEffect(settingsManager.fitnessLevel == level ? 1.0 : 0.5)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: settingsManager.fitnessLevel)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.15) : .gray.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(settingsManager.fitnessLevel == level ? .accent.opacity(0.5) :
                                   (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1)),
                                   lineWidth: settingsManager.fitnessLevel == level ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.accent.opacity(0.8))

                Text("How it works")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            }

            Text("Your fitness level sets initial thresholds for heat map colors during your first 10 workouts. After that, scoring automatically transitions to personalized percentile-based scoring using your workout history.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.15) : .gray.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

#Preview("Light Theme") {
    NavigationStack {
        FitnessLevelSelectionView()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Theme") {
    NavigationStack {
        FitnessLevelSelectionView()
    }
    .preferredColorScheme(.dark)
}
