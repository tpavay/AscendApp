//
//  FitnessLevelOnboardingView.swift
//  AscendApp
//
//  Onboarding view for users to select their fitness level.
//  This is used to set initial scoring thresholds before
//  the user has enough workout history for percentile scoring.
//

import SwiftUI

struct FitnessLevelOnboardingView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var selectedLevel: FitnessLevel?

    let onComplete: () -> Void

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        SinglePageOnboarding(
            buttonTitle: "Continue",
            canProceed: selectedLevel != nil,
            onComplete: {
                if let level = selectedLevel {
                    settingsManager.setFitnessLevel(level)
                }
                onComplete()
            }
        ) {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 20)

                // Header
                headerSection

                // Fitness Level Options
                VStack(spacing: 12) {
                    ForEach(FitnessLevel.allCases) { level in
                        fitnessLevelCard(level: level)
                    }
                }
                .padding(.horizontal, 24)

                // Info text
                infoText

                Spacer()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.stairs")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.accent)

            Text("What's Your Fitness Level?")
                .font(.montserratBold(size: 24))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)

            Text("This helps us personalize your progress tracking until we learn from your workouts.")
                .font(.montserratRegular(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Fitness Level Card

    private func fitnessLevelCard(level: FitnessLevel) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedLevel = level
            }
        }) {
            HStack(alignment: .center, spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.1))
                        .frame(width: 50, height: 50)

                    Image(systemName: level.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.accent)
                }

                // Text Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.displayName)
                        .font(.montserratSemiBold(size: 17))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Text(level.description)
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(
                            selectedLevel == level ? .accent : (effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3)),
                            lineWidth: 2
                        )
                        .frame(width: 24, height: 24)

                    if selectedLevel == level {
                        Circle()
                            .fill(.accent)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.15) : .gray.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                selectedLevel == level ? .accent.opacity(0.6) :
                                    (effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1)),
                                lineWidth: selectedLevel == level ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Info Text

    private var infoText: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(.accent.opacity(0.8))

            Text("You can change this anytime in Settings")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.7))
        }
        .padding(.horizontal, 24)
    }
}

#Preview("Light") {
    FitnessLevelOnboardingView {
        print("Onboarding complete")
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    FitnessLevelOnboardingView {
        print("Onboarding complete")
    }
    .preferredColorScheme(.dark)
}
