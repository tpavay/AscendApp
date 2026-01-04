//
//  DetailedSummaryCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/26/25.
//

import SwiftUI

/// Full stats summary card with workout details, supports light/dark themes
struct DetailedSummaryCard: View {
    let workout: Workout
    let theme: ShareCardTheme
    let measurementSystem: MeasurementSystem
    let stepHeight: Double
    let preferredMetric: WorkoutMetric
    let displayName: String

    // MARK: - Weight Formatting

    private var formattedTotalWeight: String? {
        guard workout.hasWeights else { return nil }
        let weight = workout.totalWeightUsed
        let formatted = weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
        return "\(formatted) \(measurementSystem.weightAbbreviation)"
    }

    var body: some View {
        ShareableCardContainer(theme: theme, displayName: displayName) {
            VStack(alignment: .leading, spacing: 24) {
                titleView
                
                metricsGrid
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }
    
    // MARK: - Title
    
    private var titleView: some View {
        Text(workoutTitle)
            .font(.montserratBold(size: 22))
            .foregroundStyle(theme.textColor)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var workoutTitle: String {
        workout.name.isEmpty ? "Stair workout" : workout.name
    }
    
    // MARK: - Stats Grid
    // Layout:
    // Row 1: Duration (always) | Steps/Floors (always)
    // Row 2: Steps/Min or Floors/Min | Calories or Vertical Climb
    // Row 3 (if PRs): Records count with badge

    private var metricsGrid: some View {
        VStack(spacing: 28) {
            // Row 1: Duration | Steps/Floors
            HStack(spacing: 24) {
                metricBlock(value: workout.durationFormatted, label: "Duration")
                metricBlock(value: primaryMetricValue, label: preferredMetric.displayName)
            }

            // Row 2: Pace | Calories or Vertical Climb
            HStack(spacing: 24) {
                // Left: Pace (Steps/Min or Floors/Min)
                if let paceInfo = paceValue {
                    metricBlock(
                        value: paceInfo.value,
                        label: paceInfo.label
                    )
                } else {
                    metricBlock(value: "—", label: preferredMetric == .steps ? "Steps/Min" : "Floors/Min")
                }

                // Right: Calories or Vertical Climb
                if hasCalories {
                    metricBlock(value: caloriesValue, label: "Calories")
                } else if let vertical = verticalClimbValue {
                    metricBlock(value: vertical, label: "Vertical Climb")
                } else {
                    metricBlock(value: "—", label: "Calories")
                }
            }

            // Row 3: Added Weight (only if weights used)
            if let weightText = formattedTotalWeight {
                HStack(spacing: 24) {
                    metricBlock(
                        value: weightText,
                        label: "Added Weight",
                        accessory: AnyView(
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.accent)
                        )
                    )
                    // Empty spacer to maintain grid alignment
                    Spacer()
                        .frame(maxWidth: .infinity)
                }
            }

            // Row 4: Personal Records (only if any)
            if workout.hasPersonalRecords {
                HStack(spacing: 24) {
                    metricBlock(
                        value: "\(workout.achievedPersonalRecords.count)",
                        label: "Records",
                        accessory: AnyView(
                            Image(systemName: "medal.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.yellow)
                        )
                    )
                    // Empty spacer to maintain grid alignment
                    Spacer()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private func metricBlock(
        value: String,
        label: String,
        accessory: AnyView? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.montserratBold(size: 26))
                .foregroundStyle(theme.textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            HStack(spacing: 6) {
                Text(label)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(theme.secondaryTextColor)
                
                if let accessory {
                    accessory
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var formattedMetricValue: String {
        let value = workout.metricValue(for: preferredMetric)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private var primaryMetricValue: String {
        "\(formattedMetricValue) \(preferredMetric.unit)"
    }
    
    private var hasCalories: Bool {
        workout.caloriesBurned != nil
    }
    
    private var caloriesValue: String {
        guard let calories = workout.caloriesBurned else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: calories)) ?? "\(calories)")"
    }
    
    private var paceValue: (label: String, value: String)? {
        guard let pace = workout.pace(for: preferredMetric) else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let value = formatter.string(from: NSNumber(value: pace)) ?? String(format: "%.0f", pace)
        let label = preferredMetric == .steps ? "Steps/Min" : "Floors/Min"
        return (label, value)
    }
    
    private var verticalClimbValue: String? {
        guard workout.steps > 0 else { return nil }
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
}

#Preview("Dark Theme") {
    DetailedSummaryCard(
        workout: Workout(
            name: "Morning Stair Climb",
            duration: 1800,
            steps: 2500,
            floors: 156,
            stepsPerFloor: 16,
            avgHeartRate: 145,
            maxHeartRate: 165,
            caloriesBurned: 320,
            personalRecordTypes: ["mostSteps", "longestDuration"]
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

#Preview("Light Theme") {
    DetailedSummaryCard(
        workout: Workout(
            name: "Evening Session",
            duration: 2400,
            steps: 3200,
            floors: 200,
            stepsPerFloor: 16,
            caloriesBurned: 450
        ),
        theme: .light,
        measurementSystem: .imperial,
        stepHeight: 0.18,
        preferredMetric: .floors,
        displayName: "tpavay"
    )
    .frame(width: WorkoutShareCarouselViewModel.displayCardWidth)
    .padding()
    .background(Color.gray.opacity(0.2))
}

