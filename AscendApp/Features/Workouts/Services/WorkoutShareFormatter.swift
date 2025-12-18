//
//  WorkoutShareFormatter.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/5/25.
//

import Foundation

func workoutShareText(
    for workout: Workout,
    measurementSystem: MeasurementSystem,
    stepHeight: Double,
    preferredMetric: WorkoutMetric
) -> String {
    let workoutTitle = workout.name.isEmpty ? "Stair workout" : workout.name
    let achievedPRs = Set(workout.achievedPersonalRecords)

    var lines: [String] = [
        workoutTitle,
        ""
    ]

    // Duration
    let durationPR = achievedPRs.contains(.longestDuration) ? " (PR)" : ""
    lines.append("Duration: \(workout.durationFormatted)\(durationPR)")

    // Primary metric (steps or floors)
    if let metricLine = primaryMetricLine(for: workout, preferredMetric: preferredMetric, achievedPRs: achievedPRs) {
        lines.append(metricLine)
    }

    // Pace
    if let pace = workout.pace(for: preferredMetric) {
        let paceText = formattedDecimal(pace, decimals: 1)
        let paceUnit = preferredMetric == .steps ? "steps/min" : "floors/min"
        let pacePR = achievedPRs.contains(.highestAveragePace) ? " (PR)" : ""
        lines.append("Pace: \(paceText) \(paceUnit)\(pacePR)")
    }

    // Vertical climb
    if workout.steps > 0 {
        let vertical = workout.totalVerticalClimb(
            stepHeight: stepHeight,
            measurementSystem: measurementSystem
        )
        let verticalText = formattedDecimal(vertical, decimals: vertical < 100 ? 1 : 0)
        let verticalPR = achievedPRs.contains(.highestVerticalClimb) ? " (PR)" : ""
        lines.append("Vertical Climb: \(verticalText) \(measurementSystem.distanceAbbreviation)\(verticalPR)")
    }

    // Avg heart rate
    if let avgHR = workout.avgHeartRate {
        let avgHRPR = achievedPRs.contains(.highestAverageHeartRate) ? " (PR)" : ""
        lines.append("Avg Heart Rate: \(avgHR) BPM\(avgHRPR)")
    }

    // Max heart rate
    if let maxHR = workout.maxHeartRate {
        let maxHRPR = achievedPRs.contains(.highestMaxHeartRate) ? " (PR)" : ""
        lines.append("Max Heart Rate: \(maxHR) BPM\(maxHRPR)")
    }

    // Add attribution at the bottom
    lines.append("")
    lines.append("Logged with Ascend")

    return lines.joined(separator: "\n")
}

private func primaryMetricLine(for workout: Workout, preferredMetric: WorkoutMetric, achievedPRs: Set<PersonalRecordType>) -> String? {
    let value = workout.metricValue(for: preferredMetric)
    let formattedValue = formattedInteger(value)
    switch preferredMetric {
    case .steps:
        let stepsPR = achievedPRs.contains(.mostSteps) ? " (PR)" : ""
        return "Steps: \(formattedValue)\(stepsPR)"
    case .floors:
        let floorsPR = achievedPRs.contains(.mostFloors) ? " (PR)" : ""
        return "Floors: \(formattedValue)\(floorsPR)"
    }
}

private func formattedInteger(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func formattedDecimal(_ value: Double, decimals: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = decimals
    formatter.minimumFractionDigits = decimals
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
}
