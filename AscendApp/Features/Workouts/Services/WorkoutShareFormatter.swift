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
    stepHeight: Double
) -> String {
    let workoutTitle = workout.name.isEmpty ? "Stair workout" : workout.name
    var lines: [String] = [
        "\(workoutTitle) logged with Ascend 🧗‍♂️",
        ""
    ]

    lines.append("Duration: \(workout.durationFormatted)")

    if let metricLine = primaryMetricLine(for: workout) {
        lines.append(metricLine)
    }

    if let pace = workout.pace {
        let paceText = formattedDecimal(pace, decimals: 1)
        let paceUnit = workout.metricType == .steps ? "steps/min" : "floors/min"
        lines.append("Pace: \(paceText) \(paceUnit)")
    }

    if let vertical = workout.totalVerticalClimb(
        stepHeight: stepHeight,
        measurementSystem: measurementSystem
    ) {
        let verticalText = formattedDecimal(vertical, decimals: vertical < 100 ? 1 : 0)
        lines.append("Vertical Climb: \(verticalText) \(measurementSystem.distanceAbbreviation)")
    }

    if let avgHR = workout.avgHeartRate {
        lines.append("Avg Heart Rate: \(avgHR) BPM")
    }

    if let maxHR = workout.maxHeartRate {
        lines.append("Max Heart Rate: \(maxHR) BPM")
    }

    return lines.joined(separator: "\n")
}

private func primaryMetricLine(for workout: Workout) -> String? {
    guard let value = workout.primaryMetricValue else { return nil }
    let formattedValue = formattedInteger(value)
    switch workout.metricType {
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
