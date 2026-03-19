//
//  WorkoutTestDataSeeder.swift
//  AscendApp
//
//  Created by Codex on 3/10/26.
//

import Foundation
import SwiftData
@preconcurrency import FirebaseAuth

#if DEBUG
enum WorkoutSeedPreset: String, CaseIterable, Identifiable {
    case appStoreScreenshots = "app_store_screenshots"
    case quickDemo = "quick_demo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appStoreScreenshots:
            return "App Store Screenshots"
        case .quickDemo:
            return "Quick Demo"
        }
    }

    var pickerLabel: String {
        switch self {
        case .appStoreScreenshots:
            return "Screenshots"
        case .quickDemo:
            return "Quick Demo"
        }
    }
}

@MainActor
final class WorkoutTestDataSeeder {
    private let settings = SettingsManager.shared
    private let seedSource = "debug-tools"

    func seedWorkouts(
        preset: WorkoutSeedPreset,
        modelContext: ModelContext
    ) async throws -> Int {
        try removeSeededWorkouts(modelContext: modelContext)

        let generatedWorkouts = generateWorkouts(for: preset, referenceDate: Date())
        for workout in generatedWorkouts {
            modelContext.insert(workout)
        }
        try modelContext.save()

        try rebuildDerivedData(modelContext: modelContext)
        return generatedWorkouts.count
    }

    func clearSeededWorkouts(modelContext: ModelContext) throws -> Int {
        let seededWorkouts = try fetchSeededWorkouts(modelContext: modelContext)
        guard !seededWorkouts.isEmpty else { return 0 }

        for workout in seededWorkouts {
            modelContext.delete(workout)
        }
        try modelContext.save()

        try rebuildDerivedData(modelContext: modelContext)
        return seededWorkouts.count
    }

    // MARK: - Generators

    private func generateWorkouts(
        for preset: WorkoutSeedPreset,
        referenceDate: Date
    ) -> [Workout] {
        switch preset {
        case .appStoreScreenshots:
            return generateScreenshotPreset(referenceDate: referenceDate)
        case .quickDemo:
            return generateQuickDemoPreset(referenceDate: referenceDate)
        }
    }

    private func generateScreenshotPreset(referenceDate: Date) -> [Workout] {
        let calendar = Calendar.current
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -89, to: referenceDate) ?? referenceDate
        let firstDay = calendar.startOfDay(for: ninetyDaysAgo)
        var rng = SeededGenerator(seed: 78_000_026)
        var workouts: [Workout] = []

        for weekIndex in 0..<13 {
            let phase = phaseProfile(forWeek: weekIndex)
            guard let weekStart = calendar.date(byAdding: .day, value: weekIndex * 7, to: firstDay),
                  let weekEndCandidate = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                continue
            }

            let weekEnd = min(weekEndCandidate, referenceDate)
            let maxOffset = max(
                0,
                calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: weekStart),
                    to: calendar.startOfDay(for: weekEnd)
                ).day ?? 0
            )

            let desiredCount = Int.random(in: phase.workoutsPerWeek, using: &rng)
            let workoutCount = min(desiredCount, maxOffset + 1)
            guard workoutCount > 0 else { continue }

            let dayOffsets = uniqueDayOffsets(maxOffset: maxOffset, count: workoutCount, rng: &rng)
            for dayOffset in dayOffsets {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart),
                      let timestamp = randomWorkoutTimestamp(on: day, referenceDate: referenceDate, rng: &rng) else {
                    continue
                }

                workouts.append(
                    buildWorkout(
                        date: timestamp,
                        phase: phase,
                        preset: .appStoreScreenshots,
                        rng: &rng
                    )
                )
            }
        }

        return workouts.sorted { $0.date < $1.date }
    }

    private func generateQuickDemoPreset(referenceDate: Date) -> [Workout] {
        let calendar = Calendar.current
        let dayOffsets = [10, 8, 6, 3, 1]
        var rng = SeededGenerator(seed: 78_000_101)
        var workouts: [Workout] = []

        for (index, daysAgo) in dayOffsets.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: referenceDate),
                  let timestamp = randomWorkoutTimestamp(on: day, referenceDate: referenceDate, rng: &rng) else {
                continue
            }

            let phase = index < 2 ? WorkoutPhaseProfile.phaseTwo : WorkoutPhaseProfile.phaseThree
            workouts.append(
                buildWorkout(
                    date: timestamp,
                    phase: phase,
                    preset: .quickDemo,
                    rng: &rng
                )
            )
        }

        return workouts.sorted { $0.date < $1.date }
    }

    private func buildWorkout(
        date: Date,
        phase: WorkoutPhaseProfile,
        preset: WorkoutSeedPreset,
        rng: inout SeededGenerator
    ) -> Workout {
        let stepsPerFloor = max(settings.stepsPerFloor, 1)
        let steps = Int.random(in: phase.stepRange, using: &rng)
        let pace = Double.random(in: phase.paceRange, using: &rng)
        let minutes = clamped(
            Double(steps) / pace,
            min: phase.durationMinutesRange.lowerBound,
            max: phase.durationMinutesRange.upperBound
        )
        let duration = max(10 * 60, (minutes * 60).rounded())
        let floors = Workout.stepsToFloors(steps, stepsPerFloor: stepsPerFloor)

        let hasHeartRate = chance(0.70, rng: &rng)
        let avgHeartRate = hasHeartRate ? Int.random(in: phase.avgHeartRateRange, using: &rng) : nil
        let maxHeartRate = avgHeartRate.map { min($0 + Int.random(in: 10...30, using: &rng), 205) }
        let heartRateTimeSeries = buildHeartRateSeries(
            startDate: date,
            duration: duration,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            rng: &rng
        )

        let effortRating: Double?
        if chance(0.60, rng: &rng) {
            let rawEffort = Double.random(in: phase.effortRange, using: &rng)
            effortRating = roundedToTenths(rawEffort)
        } else {
            effortRating = nil
        }

        let weightConfiguration = weightedVestConfigurationIfNeeded(
            for: phase,
            rng: &rng
        )

        let caloriesBurned = estimateCalories(
            steps: steps,
            durationMinutes: minutes,
            pace: pace,
            effortRating: effortRating,
            hasWeights: weightConfiguration != nil,
            phase: phase
        )

        return Workout(
            name: Workout.generateDefaultName(for: date),
            date: date,
            duration: duration,
            steps: steps,
            floors: floors,
            stepsPerFloor: stepsPerFloor,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            caloriesBurned: caloriesBurned,
            effortRating: effortRating,
            heartRateTimeSeries: heartRateTimeSeries,
            source: .manual,
            deviceModel: "Ascend Debug Seeder",
            sourceMetadata: metadataString(for: preset),
            weightConfiguration: weightConfiguration
        )
    }

    private func phaseProfile(forWeek weekIndex: Int) -> WorkoutPhaseProfile {
        switch weekIndex {
        case 0..<4:
            return .phaseOne
        case 4..<9:
            return .phaseTwo
        default:
            return .phaseThree
        }
    }

    private func randomWorkoutTimestamp(
        on day: Date,
        referenceDate: Date,
        rng: inout SeededGenerator
    ) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: day)

        let dayPartRoll = Double.random(in: 0...1, using: &rng)
        let hourRange: ClosedRange<Int>
        switch dayPartRoll {
        case ..<0.65:
            hourRange = 5...10
        case ..<0.90:
            hourRange = 12...17
        default:
            hourRange = 18...20
        }

        components.hour = Int.random(in: hourRange, using: &rng)
        components.minute = Int.random(in: 0...5, using: &rng) * 10
        components.second = 0

        guard let candidate = calendar.date(from: components) else { return nil }
        let latestAllowed = referenceDate.addingTimeInterval(-5 * 60)
        return candidate > latestAllowed ? latestAllowed : candidate
    }

    private func buildHeartRateSeries(
        startDate: Date,
        duration: TimeInterval,
        avgHeartRate: Int?,
        maxHeartRate: Int?,
        rng: inout SeededGenerator
    ) -> [HeartRateDataPoint]? {
        guard let avgHeartRate, let maxHeartRate else { return nil }

        let pointCount = max(8, Int(duration / 120))
        guard pointCount > 1 else { return nil }

        let lowerBound = max(95, avgHeartRate - 15)
        var dataPoints: [HeartRateDataPoint] = []
        dataPoints.reserveCapacity(pointCount)

        for index in 0..<pointCount {
            let progress = Double(index) / Double(max(pointCount - 1, 1))
            let wave = sin(progress * .pi * 2.5) * 8
            let noise = Double(Int.random(in: -3...3, using: &rng))
            let heartRate = Int((Double(avgHeartRate) + wave + noise).rounded())
            let clampedHeartRate = Int(clamped(Double(heartRate), min: Double(lowerBound), max: Double(maxHeartRate)))
            let timestamp = startDate.addingTimeInterval(progress * duration)
            dataPoints.append(HeartRateDataPoint(timestamp: timestamp, heartRate: clampedHeartRate))
        }

        return dataPoints
    }

    private func weightedVestConfigurationIfNeeded(
        for phase: WorkoutPhaseProfile,
        rng: inout SeededGenerator
    ) -> WeightConfiguration? {
        guard phase.includesWeightedVest, chance(0.30, rng: &rng) else { return nil }

        let intendedPounds = Double.random(in: 15...25, using: &rng)
        let storedWeight: Double
        switch settings.measurementSystem {
        case .imperial:
            storedWeight = intendedPounds
        case .metric:
            storedWeight = MeasurementSystem.imperial.convertWeight(intendedPounds, to: .metric)
        }

        let roundedWeight = roundedToTenths(storedWeight)
        let entry = WeightEntry(
            equipmentType: .weightedVest,
            weightValue: max(roundedWeight, 0.5),
            isEnabled: true
        )
        return WeightConfiguration(entries: [entry])
    }

    private func estimateCalories(
        steps: Int,
        durationMinutes: Double,
        pace: Double,
        effortRating: Double?,
        hasWeights: Bool,
        phase: WorkoutPhaseProfile
    ) -> Int {
        let paceSpan = phase.paceRange.upperBound - phase.paceRange.lowerBound
        let paceRatio = paceSpan > 0
            ? clamped((pace - phase.paceRange.lowerBound) / paceSpan, min: 0, max: 1)
            : 0.5
        let effort = effortRating ?? ((phase.effortRange.lowerBound + phase.effortRange.upperBound) / 2)
        let effortBoost = max(0, effort - 1.0) * 0.7
        let weightBoost = hasWeights ? 1.2 : 0
        let burnPerMinute = 7.0 + (paceRatio * 3.0) + effortBoost + weightBoost
        let stepsBoost = Double(steps) * 0.01

        return max(60, Int((burnPerMinute * durationMinutes + stepsBoost).rounded()))
    }

    // MARK: - Cleanup + Rebuild

    private func removeSeededWorkouts(modelContext: ModelContext) throws {
        let existingSeededWorkouts = try fetchSeededWorkouts(modelContext: modelContext)
        guard !existingSeededWorkouts.isEmpty else { return }

        for workout in existingSeededWorkouts {
            modelContext.delete(workout)
        }
        try modelContext.save()
    }

    private func fetchSeededWorkouts(modelContext: ModelContext) throws -> [Workout] {
        let allWorkouts = try modelContext.fetch(FetchDescriptor<Workout>())
        return allWorkouts.filter(isSeededWorkout)
    }

    private func isSeededWorkout(_ workout: Workout) -> Bool {
        guard let metadata = metadata(from: workout) else { return false }
        return metadata.isTestData && metadata.seedSource == seedSource
    }

    private func rebuildDerivedData(modelContext: ModelContext) throws {
        try WorkoutMutationHandler.shared.workoutsDidChange(modelContext: modelContext)
    }

    // MARK: - Metadata

    private func metadataString(for preset: WorkoutSeedPreset) -> String {
        let metadata = SeededWorkoutMetadata(
            isTestData: true,
            seedSource: seedSource,
            preset: preset.rawValue
        )

        if let data = try? JSONEncoder().encode(metadata),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }

        return "{\"isTestData\":true,\"seedSource\":\"\(seedSource)\",\"preset\":\"\(preset.rawValue)\"}"
    }

    private func metadata(from workout: Workout) -> SeededWorkoutMetadata? {
        guard let sourceMetadata = workout.sourceMetadata,
              let data = sourceMetadata.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(SeededWorkoutMetadata.self, from: data)
    }
}

private struct WorkoutPhaseProfile {
    let stepRange: ClosedRange<Int>
    let durationMinutesRange: ClosedRange<Double>
    let avgHeartRateRange: ClosedRange<Int>
    let effortRange: ClosedRange<Double>
    let paceRange: ClosedRange<Double>
    let workoutsPerWeek: ClosedRange<Int>
    let includesWeightedVest: Bool

    static let phaseOne = WorkoutPhaseProfile(
        stepRange: 500...1_200,
        durationMinutesRange: 15...25,
        avgHeartRateRange: 120...140,
        effortRange: 1.5...3.0,
        paceRange: 35...55,
        workoutsPerWeek: 2...3,
        includesWeightedVest: false
    )

    static let phaseTwo = WorkoutPhaseProfile(
        stepRange: 1_000...2_000,
        durationMinutesRange: 20...35,
        avgHeartRateRange: 130...150,
        effortRange: 2.5...3.5,
        paceRange: 45...65,
        workoutsPerWeek: 2...3,
        includesWeightedVest: false
    )

    static let phaseThree = WorkoutPhaseProfile(
        stepRange: 1_500...2_800,
        durationMinutesRange: 25...45,
        avgHeartRateRange: 135...165,
        effortRange: 3.0...4.5,
        paceRange: 55...75,
        workoutsPerWeek: 3...4,
        includesWeightedVest: true
    )
}

private struct SeededWorkoutMetadata: Codable {
    let isTestData: Bool
    let seedSource: String
    let preset: String?
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xCAFE_BABE_F00D : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }
}

private func uniqueDayOffsets(
    maxOffset: Int,
    count: Int,
    rng: inout SeededGenerator
) -> [Int] {
    guard maxOffset >= 0, count > 0 else { return [] }
    var offsets = Array(0...maxOffset)
    offsets.shuffle(using: &rng)
    return Array(offsets.prefix(count)).sorted()
}

private func chance(
    _ probability: Double,
    rng: inout SeededGenerator
) -> Bool {
    Double.random(in: 0...1, using: &rng) <= clamped(probability, min: 0, max: 1)
}

private func roundedToTenths(_ value: Double) -> Double {
    (value * 10).rounded() / 10
}

private func clamped<T: Comparable>(_ value: T, min lowerBound: T, max upperBound: T) -> T {
    Swift.min(upperBound, Swift.max(lowerBound, value))
}
#endif
