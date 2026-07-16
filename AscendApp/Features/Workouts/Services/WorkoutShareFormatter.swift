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
    bestEffort: RankedBestEffort? = nil
) -> String {
    let workoutTitle = workout.name.isEmpty ? "Stair workout" : workout.name

    var lines: [String] = [
        workoutTitle,
        ""
    ]

    lines.append("Duration: \(workout.durationFormatted)")

    lines.append("Steps: \(formattedInteger(workout.steps))")

    // Added Weight
    if workout.hasWeights {
        let weight = workout.totalWeightUsed
        let formatted = weight.truncatingRemainder(dividingBy: 1) == 0
            ? weight.formatted(.number.precision(.fractionLength(0)))
            : weight.formatted(.number.precision(.fractionLength(1)))
        lines.append("Added Weight: \(formatted) \(measurementSystem.weightAbbreviation)")
    }

    // Pace
    if let pace = workout.stepsPerMinute {
        let paceText = formattedDecimal(pace, decimals: 1)
        lines.append("Pace: \(paceText) steps/min")
    }

    if let bestEffort {
        lines.append("Best Effort: \(bestEffort.sentence)")
    }

    // Vertical climb
    if workout.steps > 0 {
        let vertical = workout.totalVerticalClimb(
            stepHeight: stepHeight,
            measurementSystem: measurementSystem
        )
        let verticalText = formattedDecimal(vertical, decimals: vertical < 100 ? 1 : 0)
        lines.append("Vertical Climb: \(verticalText) \(measurementSystem.distanceAbbreviation)")
    }

    // Avg heart rate
    if let avgHR = workout.avgHeartRate {
        lines.append("Avg Heart Rate: \(avgHR) BPM")
    }

    // Max heart rate
    if let maxHR = workout.maxHeartRate {
        lines.append("Max Heart Rate: \(maxHR) BPM")
    }

    // Add attribution at the bottom
    lines.append("")
    lines.append("Logged with Ascend")

    return lines.joined(separator: "\n")
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
    return formatter.string(from: NSNumber(value: value)) ?? value.formatted(.number.precision(.fractionLength(decimals)))
}
