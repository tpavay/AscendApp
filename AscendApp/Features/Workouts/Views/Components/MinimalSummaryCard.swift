//
//  MinimalSummaryCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 1/26/26.
//

import SwiftUI

/// Minimal stats card inspired by Strava's transparent share card design
/// Shows primary metric, vertical climb, and duration in a clean centered layout
struct MinimalSummaryCard: View {
    let workout: Workout
    let theme: ShareCardTheme
    let measurementSystem: MeasurementSystem
    let stepHeight: Double
    let preferredMetric: WorkoutMetric
    let displayName: String

    private var brandingColor: Color {
        theme == .dark ? .white.opacity(0.9) : .black.opacity(0.7)
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch theme {
        case .dark:
            LinearGradient(
                colors: [.night, .jetLighter],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            Color.white
        }
    }

    var body: some View {
        ZStack {
            // Gradient background
            cardBackground

            // Content
            VStack(spacing: 0) {
                Spacer()

                // Metrics stack
                VStack(spacing: 28) {
                    metricView(label: preferredMetric.displayName, value: primaryMetricValue)
                    metricView(label: "Vertical Climb", value: verticalClimbValue)
                    metricView(label: "Time", value: formattedDuration)
                }

                Spacer()

                // Branding at bottom
                VStack(spacing: 8) {
                    Image("AppIconInternal")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(brandingColor)
                        .frame(width: 36, height: 36)

                    Text("ASCEND")
                        .font(.montserratBold(size: 14))
                        .tracking(2)
                        .foregroundStyle(brandingColor)
                }
                .padding(.bottom, 24)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: WorkoutShareCarouselViewModel.displayCardHeight,
            maxHeight: WorkoutShareCarouselViewModel.displayCardHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }

    // MARK: - Metric View

    private func metricView(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(theme.secondaryTextColor)

            Text(value)
                .font(.montserratBold(size: 32))
                .foregroundStyle(theme.textColor)
        }
    }

    // MARK: - Computed Values

    private var primaryMetricValue: String {
        let value = workout.metricValue(for: preferredMetric)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var verticalClimbValue: String {
        guard workout.steps > 0 else { return "0 \(measurementSystem.distanceAbbreviation)" }
        let vertical = workout.totalVerticalClimb(
            stepHeight: stepHeight,
            measurementSystem: measurementSystem
        )
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = vertical < 100 ? 1 : 0
        let value = formatter.string(from: NSNumber(value: vertical)) ?? String(format: "%.0f", vertical)
        return "\(value) \(measurementSystem.distanceAbbreviation)"
    }

    private var formattedDuration: String {
        let hours = Int(workout.duration) / 3600
        let minutes = Int(workout.duration) % 3600 / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Previews

#Preview("Dark Theme - Steps") {
    MinimalSummaryCard(
        workout: Workout(
            name: "Morning Climb",
            duration: 3660, // 1h 1m
            steps: 5708,
            floors: 357,
            stepsPerFloor: 16
        ),
        theme: .dark,
        measurementSystem: .imperial,
        stepHeight: 0.18,
        preferredMetric: .steps,
        displayName: "tpavay"
    )
    .frame(width: WorkoutShareCarouselViewModel.displayCardWidth)
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("Dark Theme - Floors") {
    MinimalSummaryCard(
        workout: Workout(
            name: "Evening Session",
            duration: 2400,
            steps: 3200,
            floors: 200,
            stepsPerFloor: 16
        ),
        theme: .dark,
        measurementSystem: .imperial,
        stepHeight: 0.18,
        preferredMetric: .floors,
        displayName: "tpavay"
    )
    .frame(width: WorkoutShareCarouselViewModel.displayCardWidth)
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("Light Theme") {
    MinimalSummaryCard(
        workout: Workout(
            name: "Afternoon Climb",
            duration: 1800,
            steps: 2500,
            floors: 156,
            stepsPerFloor: 16
        ),
        theme: .light,
        measurementSystem: .metric,
        stepHeight: 0.18,
        preferredMetric: .steps,
        displayName: "tpavay"
    )
    .frame(width: WorkoutShareCarouselViewModel.displayCardWidth)
    .padding()
    .background(Color.gray.opacity(0.2))
}
