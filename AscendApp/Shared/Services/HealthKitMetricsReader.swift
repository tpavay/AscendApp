//
//  HealthKitMetricsReader.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import Foundation
import HealthKit

struct WorkoutMetrics {
    var steps: Int?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var caloriesBurned: Int?
    var restingCaloriesBurned: Int?
    var heartRateTimeSeries: [HeartRateDataPoint] = []
    var averageMETs: Double?
}

@MainActor
protocol HealthKitMetricsReading {
    func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics
    func fetchMetrics(for workout: HKWorkout, during dateRange: ClosedRange<Date>) async -> WorkoutMetrics
}

extension HealthKitMetricsReading {
    func fetchMetrics(for workout: HKWorkout, during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
        await fetchMetrics(for: workout)
    }
}

@MainActor
final class HealthKitMetricsReader: HealthKitMetricsReading {
    static let shared = HealthKitMetricsReader()

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics {
        await fetchMetrics(for: workout, during: workout.startDate...workout.endDate)
    }

    func fetchMetrics(for workout: HKWorkout, during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
        var metrics = WorkoutMetrics()

        if let stepCount = await fetchQuantityData(for: .stepCount, during: dateRange, unit: .count()) {
            metrics.steps = Int(stepCount)
        }

        let heartRateData = await fetchHeartRateData(during: dateRange)
        metrics.avgHeartRate = heartRateData.average
        metrics.maxHeartRate = heartRateData.maximum
        metrics.heartRateTimeSeries = await fetchHeartRateTimeSeries(during: dateRange)

        if let avgMetsQuantity = workout.metadata?["HKAverageMETs"] as? HKQuantity {
            let metsUnit = HKUnit.kilocalorie().unitDivided(
                by: HKUnit.hour().unitMultiplied(by: HKUnit.gramUnit(with: .kilo))
            )
            metrics.averageMETs = avgMetsQuantity.doubleValue(for: metsUnit)
        }

        if let calories = await fetchQuantityData(for: .activeEnergyBurned, during: dateRange, unit: .kilocalorie()) {
            metrics.caloriesBurned = Int(calories)
        }

        if let restingCalories = await fetchQuantityData(for: .basalEnergyBurned, during: dateRange, unit: .kilocalorie()) {
            metrics.restingCaloriesBurned = Int(restingCalories)
        }

        return metrics
    }

    private func fetchQuantityData(
        for identifier: HKQuantityTypeIdentifier,
        during dateRange: ClosedRange<Date>,
        unit: HKUnit
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: dateRange.lowerBound, end: dateRange.upperBound)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let sum = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: sum > 0 ? sum : nil)
            }

            healthStore.execute(query)
        }
    }

    private func fetchHeartRateData(
        during dateRange: ClosedRange<Date>
    ) async -> (average: Int?, maximum: Int?) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil)
        }

        let predicate = HKQuery.predicateForSamples(withStart: dateRange.lowerBound, end: dateRange.upperBound)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, result, _ in
                let average = result?.averageQuantity()?.doubleValue(for: unit)
                let maximum = result?.maximumQuantity()?.doubleValue(for: unit)

                continuation.resume(
                    returning: (
                        average: average.map(Int.init),
                        maximum: maximum.map(Int.init)
                    )
                )
            }

            healthStore.execute(query)
        }
    }

    private func fetchHeartRateTimeSeries(during dateRange: ClosedRange<Date>) async -> [HeartRateDataPoint] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: dateRange.lowerBound, end: dateRange.upperBound)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let dataPoints = (samples as? [HKQuantitySample])?.map { sample in
                    HeartRateDataPoint(
                        timestamp: sample.startDate,
                        heartRate: Int(sample.quantity.doubleValue(for: unit))
                    )
                } ?? []

                continuation.resume(returning: dataPoints)
            }

            healthStore.execute(query)
        }
    }
}

extension HKWorkout {
    func toAscendWorkout(with metrics: WorkoutMetrics, stepsPerFloor: Int) -> Workout {
        let deviceName = sourceRevision.source.name
        let isFromAppleWatch = deviceName.contains("Apple Watch") || deviceName.contains("Watch")
        let sourceMetadata = """
        {
            "sourceDevice": "\(deviceName)",
            "sourceBundleIdentifier": "\(sourceRevision.source.bundleIdentifier)",
            "workoutActivityType": "\(workoutActivityType.rawValue)",
            "isFromAppleWatch": \(isFromAppleWatch)
        }
        """

        let steps = metrics.steps ?? 0
        let floors = Workout.stepsToFloors(steps, stepsPerFloor: stepsPerFloor)

        return Workout(
            name: Workout.generateDefaultName(for: startDate),
            date: startDate,
            duration: duration,
            steps: steps,
            floors: floors,
            stepsPerFloor: stepsPerFloor,
            avgHeartRate: metrics.avgHeartRate,
            maxHeartRate: metrics.maxHeartRate,
            caloriesBurned: metrics.caloriesBurned,
            heartRateTimeSeries: metrics.heartRateTimeSeries,
            averageMETs: metrics.averageMETs,
            source: .appleHealth,
            deviceModel: device?.name ?? deviceName,
            sourceMetadata: sourceMetadata,
            healthKitUUID: uuid.uuidString
        )
    }
}
