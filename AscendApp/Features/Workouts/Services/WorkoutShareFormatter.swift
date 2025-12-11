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
    var lines: [String] = [
        workoutTitle,
        ""
    ]

    lines.append("Duration: \(workout.durationFormatted)")

    if let metricLine = primaryMetricLine(for: workout, preferredMetric: preferredMetric) {
        lines.append(metricLine)
    }

    if let pace = workout.pace(for: preferredMetric) {
        let paceText = formattedDecimal(pace, decimals: 1)
        let paceUnit = preferredMetric == .steps ? "steps/min" : "floors/min"
        lines.append("Pace: \(paceText) \(paceUnit)")
    }

    if workout.steps > 0 {
        let vertical = workout.totalVerticalClimb(
            stepHeight: stepHeight,
            measurementSystem: measurementSystem
        )
        let verticalText = formattedDecimal(vertical, decimals: vertical < 100 ? 1 : 0)
        lines.append("Vertical Climb: \(verticalText) \(measurementSystem.distanceAbbreviation)")
    }

    if let avgHR = workout.avgHeartRate {
        lines.append("Avg Heart Rate: \(avgHR) BPM")
    }

    if let maxHR = workout.maxHeartRate {
        lines.append("Max Heart Rate: \(maxHR) BPM")
    }
    
    // Add personal records if any were achieved
    let prText = personalRecordsText(for: workout)
    if !prText.isEmpty {
        lines.append("")
        lines.append(prText)
    }

    // Add attribution at the bottom
    lines.append("")
    lines.append("Logged with Ascend")

    return lines.joined(separator: "\n")
}

private func primaryMetricLine(for workout: Workout, preferredMetric: WorkoutMetric) -> String? {
    let value = workout.metricValue(for: preferredMetric)
    let formattedValue = formattedInteger(value)
    switch preferredMetric {
    case .steps:
        return "Steps: \(formattedValue)"
    case .floors:
        return "Floors: \(formattedValue)"
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

private func personalRecordsText(for workout: Workout) -> String {
    let achievedRecords = workout.achievedPersonalRecords
    
    guard !achievedRecords.isEmpty else {
        return ""
    }
    
    // Create PR text with emojis
    let prLines = achievedRecords.map { recordType in
        "\(recordType.emoji) PR: \(recordType.displayName)"
    }
    
    if prLines.count == 1 {
        return prLines[0]
    } else {
        return "Personal Records:\n" + prLines.map { "  • \($0)" }.joined(separator: "\n")
    }
}
