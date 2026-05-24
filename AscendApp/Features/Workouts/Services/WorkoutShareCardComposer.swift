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
        preset: WorkoutShareCardPreset = .defaultSquarePoster,
        bestEffort: RankedBestEffort? = nil
    ) -> WorkoutShareCardComposition {
        let resolvedStats = resolvedStats(
            for: workout,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight
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
        stepHeight: Double
    ) -> [ShareCardStatKind: ShareCardResolvedStat] {
        return Dictionary(
            uniqueKeysWithValues: [
                resolvedVerticalClimb(
                    workout: workout,
                    measurementSystem: measurementSystem,
                    stepHeight: stepHeight
                ),
                resolvedStepsStat(workout: workout),
                resolvedDurationStat(workout: workout),
                resolvedCaloriesStat(workout: workout),
                resolvedPaceStat(workout: workout),
                resolvedAverageHeartRateStat(workout: workout),
                resolvedAddedWeightStat(workout: workout, measurementSystem: measurementSystem)
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

    private func resolvedStepsStat(workout: Workout) -> ShareCardResolvedStat? {
        guard workout.steps > 0 else { return nil }

        return ShareCardResolvedStat(
            kind: .steps,
            label: "STEPS",
            value: workout.steps.formatted()
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

    private func resolvedPaceStat(workout: Workout) -> ShareCardResolvedStat? {
        guard let pace = workout.stepsPerMinute, pace > 0 else { return nil }
        return ShareCardResolvedStat(
            kind: .pace,
            label: "STEPS / MIN",
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
