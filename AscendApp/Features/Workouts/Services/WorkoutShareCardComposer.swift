//
//  WorkoutShareCardComposer.swift
//  AscendApp
//
//  Created by Codex on 3/28/26.
//

import Foundation

struct WorkoutShareCardComposer {
    func compose(
        workout: Workout,
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        preferredMetric: WorkoutMetric,
        preset: WorkoutShareCardPreset = .defaultSquarePoster,
        bestEffort: RankedBestEffort? = nil
    ) -> WorkoutShareCardComposition {
        let resolvedStats = resolvedStats(
            for: workout,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            preferredMetric: preferredMetric
        )

        let heroStat = preset.heroPriority
            .compactMap { resolvedStats[$0] }
            .first ?? ShareCardResolvedStat(kind: .duration, label: "DURATION", value: workout.durationFormatted)

        let supportingStats = preset.supportingPriority
            .filter { $0 != heroStat.kind }
            .compactMap { resolvedStats[$0] }
            .prefix(preset.maxSupportingStats)

        return WorkoutShareCardComposition(
            preset: preset,
            heroStat: heroStat,
            supportingStats: Array(supportingStats),
            bestEffortText: bestEffort?.sentence
        )
    }

    private func resolvedStats(
        for workout: Workout,
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        preferredMetric: WorkoutMetric
    ) -> [ShareCardStatKind: ShareCardResolvedStat] {
        let alternateMetric: WorkoutMetric = preferredMetric == .steps ? .floors : .steps

        return Dictionary(
            uniqueKeysWithValues: [
                resolvedVerticalClimb(
                    workout: workout,
                    measurementSystem: measurementSystem,
                    stepHeight: stepHeight
                ),
                resolvedMetricStat(.preferredMetric, metric: preferredMetric, workout: workout),
                resolvedDurationStat(workout: workout),
                resolvedCaloriesStat(workout: workout),
                resolvedPaceStat(workout: workout, preferredMetric: preferredMetric),
                resolvedAverageHeartRateStat(workout: workout),
                resolvedAddedWeightStat(workout: workout, measurementSystem: measurementSystem),
                resolvedMetricStat(.alternateMetric, metric: alternateMetric, workout: workout),
            ].compactMap { $0 }.map { ($0.kind, $0) }
        )
    }

    private func resolvedVerticalClimb(
        workout: Workout,
        measurementSystem: MeasurementSystem,
        stepHeight: Double
    ) -> ShareCardResolvedStat? {
        guard workout.steps > 0 else { return nil }

        let verticalClimb = workout.totalVerticalClimb(
            stepHeight: stepHeight,
            measurementSystem: measurementSystem
        )

        guard verticalClimb > 0 else { return nil }

        let label = "\(measurementSystem.distanceUnit.uppercased()) CLIMBED"
        let value = formattedNumber(
            verticalClimb,
            maximumFractionDigits: verticalClimb < 100 ? 1 : 0
        )
        return ShareCardResolvedStat(kind: .verticalClimb, label: label, value: value)
    }

    private func resolvedMetricStat(
        _ kind: ShareCardStatKind,
        metric: WorkoutMetric,
        workout: Workout
    ) -> ShareCardResolvedStat? {
        let metricValue = workout.metricValue(for: metric)
        guard metricValue > 0 else { return nil }

        return ShareCardResolvedStat(
            kind: kind,
            label: metric.displayName.uppercased(),
            value: metricValue.formatted()
        )
    }

    private func resolvedDurationStat(workout: Workout) -> ShareCardResolvedStat? {
        guard workout.duration > 0 else { return nil }
        return ShareCardResolvedStat(kind: .duration, label: "DURATION", value: workout.durationFormatted)
    }

    private func resolvedCaloriesStat(workout: Workout) -> ShareCardResolvedStat? {
        guard let caloriesBurned = workout.caloriesBurned, caloriesBurned > 0 else { return nil }
        return ShareCardResolvedStat(
            kind: .calories,
            label: "CALORIES",
            value: caloriesBurned.formatted()
        )
    }

    private func resolvedPaceStat(
        workout: Workout,
        preferredMetric: WorkoutMetric
    ) -> ShareCardResolvedStat? {
        guard let pace = workout.pace(for: preferredMetric), pace > 0 else { return nil }
        return ShareCardResolvedStat(
            kind: .pace,
            label: preferredMetric == .steps ? "STEPS / MIN" : "FLOORS / MIN",
            value: Int(pace.rounded()).formatted()
        )
    }

    private func resolvedAverageHeartRateStat(workout: Workout) -> ShareCardResolvedStat? {
        guard let averageHeartRate = workout.avgHeartRate, averageHeartRate > 0 else { return nil }
        return ShareCardResolvedStat(
            kind: .avgHeartRate,
            label: "AVG HR",
            value: averageHeartRate.formatted()
        )
    }

    private func resolvedAddedWeightStat(
        workout: Workout,
        measurementSystem: MeasurementSystem
    ) -> ShareCardResolvedStat? {
        guard workout.hasWeights, workout.totalWeightUsed > 0 else { return nil }
        return ShareCardResolvedStat(
            kind: .addedWeight,
            label: "ADDED WEIGHT",
            value: measurementSystem.formatWeight(workout.totalWeightUsed).uppercased()
        )
    }

    private func formattedNumber(_ value: Double, maximumFractionDigits: Int) -> String {
        value.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(0...maximumFractionDigits))
        )
    }
}
