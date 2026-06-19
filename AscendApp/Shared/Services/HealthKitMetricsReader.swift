//
//  HealthKitMetricsReader.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import Foundation
import HealthKit

struct HeartRateSeriesPoint: Equatable, Sendable {
    let timestamp: Date
    let heartRate: Int
    let parentSampleId: String?
}

private final class HeartRateSeriesAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var points: [HeartRateSeriesPoint] = []
    private var errors: [String] = []

    func append(_ point: HeartRateSeriesPoint) {
        lock.withLock {
            points.append(point)
        }
    }

    func recordError(_ error: String) {
        lock.withLock {
            errors.append(error)
        }
    }

    func snapshot() -> (points: [HeartRateSeriesPoint], errors: [String]) {
        lock.withLock {
            (points, errors)
        }
    }
}

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
        metrics.heartRateTimeSeries = await fetchHeartRateTimeSeries(
            for: workout,
            during: dateRange,
            summary: heartRateData
        )

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

    private func fetchHeartRateTimeSeries(
        for workout: HKWorkout,
        during dateRange: ClosedRange<Date>,
        summary: (average: Int?, maximum: Int?)
    ) async -> [HeartRateDataPoint] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: dateRange.lowerBound, end: dateRange.upperBound)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let parentSamples = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }

            healthStore.execute(query)
        }

        let parentDataPoints = parentSamples.map { sample in
            HeartRateDataPoint(
                timestamp: sample.startDate,
                heartRate: Int(sample.quantity.doubleValue(for: unit))
            )
        }

        let seriesPoints = await fetchHeartRateSeriesPoints(
            heartRateType: heartRateType,
            predicate: predicate,
            unit: unit
        )
        let seriesDataPoints = Self.heartRateDataPoints(
            from: seriesPoints.points,
            within: dateRange
        )

        #if DEBUG
        logHeartRateImportDiagnostics(
            workout: workout,
            dateRange: dateRange,
            parentSamples: parentSamples,
            parentDataPoints: parentDataPoints,
            seriesPoints: seriesPoints,
            importedDataPoints: seriesDataPoints.isEmpty ? parentDataPoints : seriesDataPoints,
            importedFromSeries: !seriesDataPoints.isEmpty,
            unit: unit,
            summary: summary
        )
        #endif

        return seriesDataPoints.isEmpty ? parentDataPoints : seriesDataPoints
    }

    nonisolated static func heartRateDataPoints(
        from seriesPoints: [HeartRateSeriesPoint],
        within dateRange: ClosedRange<Date>
    ) -> [HeartRateDataPoint] {
        seriesPoints
            .filter { point in
                dateRange.contains(point.timestamp) && point.heartRate > 0
            }
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.heartRate < rhs.heartRate
                }
                return lhs.timestamp < rhs.timestamp
            }
            .map { point in
                HeartRateDataPoint(timestamp: point.timestamp, heartRate: point.heartRate)
            }
    }

    private func fetchHeartRateSeriesPoints(
        heartRateType: HKQuantityType,
        predicate: NSPredicate,
        unit: HKUnit
    ) async -> (points: [HeartRateSeriesPoint], errors: [String]) {
        await withCheckedContinuation { continuation in
            let accumulator = HeartRateSeriesAccumulator()
            let query = HKQuantitySeriesSampleQuery(
                quantityType: heartRateType,
                predicate: predicate
            ) { _, quantity, dateInterval, quantitySample, done, error in
                if let error {
                    accumulator.recordError(error.localizedDescription)
                }

                if let quantity, let dateInterval {
                    accumulator.append(
                        HeartRateSeriesPoint(
                            timestamp: dateInterval.start,
                            heartRate: Int(quantity.doubleValue(for: unit)),
                            parentSampleId: quantitySample?.uuid.uuidString
                        )
                    )
                }

                if done {
                    continuation.resume(returning: accumulator.snapshot())
                }
            }
            query.includeSample = true
            query.orderByQuantitySampleStartDate = true
            healthStore.execute(query)
        }
    }
}

#if DEBUG
private extension HealthKitMetricsReader {
    func logHeartRateImportDiagnostics(
        workout: HKWorkout,
        dateRange: ClosedRange<Date>,
        parentSamples: [HKQuantitySample],
        parentDataPoints: [HeartRateDataPoint],
        seriesPoints: (points: [HeartRateSeriesPoint], errors: [String]),
        importedDataPoints: [HeartRateDataPoint],
        importedFromSeries: Bool,
        unit: HKUnit,
        summary: (average: Int?, maximum: Int?)
    ) {
        let groupedSeriesCounts = Dictionary(grouping: seriesPoints.points, by: \.parentSampleId)
            .mapValues(\.count)
        let importedSource = importedFromSeries ? "quantitySeries" : "parentSamples"

        debugLog(
            """
            [HK-HR-IMPORT] workout=\(workout.uuid.uuidString) name=\(workout.workoutActivityType.rawValue) \
            range=\(Self.debugDate(dateRange.lowerBound))...\(Self.debugDate(dateRange.upperBound)) \
            duration=\(workout.duration) source=\(workout.sourceRevision.source.name) bundle=\(workout.sourceRevision.source.bundleIdentifier) \
            device=\(workout.device?.name ?? "nil") avg=\(summary.average.map(String.init) ?? "nil") max=\(summary.maximum.map(String.init) ?? "nil") \
            parentSamples=\(parentSamples.count) parentMappedPoints=\(parentDataPoints.count) seriesChildPoints=\(seriesPoints.points.count) \
            importedPoints=\(importedDataPoints.count) importedSource=\(importedSource)
            """
        )

        if !seriesPoints.errors.isEmpty {
            debugLog("[HK-HR-IMPORT] seriesErrors=\(seriesPoints.errors.joined(separator: " | "))")
        }

        logParentSamples(parentSamples, unit: unit, seriesCountsByParentId: groupedSeriesCounts)
        logSeriesPointSummary(seriesPoints.points)
    }

    func logParentSamples(
        _ samples: [HKQuantitySample],
        unit: HKUnit,
        seriesCountsByParentId: [String?: Int]
    ) {
        let indexes = Self.diagnosticIndexes(totalCount: samples.count)
        for index in indexes {
            if index == -1 {
                debugLog("[HK-HR-IMPORT] parentSamples omitted middle count=\(max(samples.count - 18, 0))")
                continue
            }

            let sample = samples[index]
            let heartRate = Int(sample.quantity.doubleValue(for: unit))
            let childCount = seriesCountsByParentId[sample.uuid.uuidString] ?? 0
            debugLog(
                """
                [HK-HR-IMPORT] parent[\(index)] uuid=\(sample.uuid.uuidString) bpm=\(heartRate) \
                count=\(sample.count) childQuantities=\(childCount) \
                start=\(Self.debugDate(sample.startDate)) end=\(Self.debugDate(sample.endDate)) \
                source=\(sample.sourceRevision.source.name) bundle=\(sample.sourceRevision.source.bundleIdentifier) \
                device=\(sample.device?.name ?? "nil")
                """
            )
        }
    }

    func logSeriesPointSummary(_ points: [HeartRateSeriesPoint]) {
        guard !points.isEmpty else { return }

        let rates = points.map(\.heartRate)
        let parentIds = Set(points.compactMap(\.parentSampleId))
        debugLog(
            """
            [HK-HR-IMPORT] seriesSummary count=\(points.count) parentIds=\(parentIds.count) \
            first=\(Self.debugDate(points[0].timestamp)):\(points[0].heartRate) \
            last=\(Self.debugDate(points[points.count - 1].timestamp)):\(points[points.count - 1].heartRate) \
            min=\(rates.min() ?? 0) max=\(rates.max() ?? 0)
            """
        )
    }

    static func diagnosticIndexes(totalCount: Int) -> [Int] {
        guard totalCount > 18 else { return Array(0..<totalCount) }
        return Array(0..<12) + [-1] + Array((totalCount - 6)..<totalCount)
    }

    static func debugDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
#endif

extension HKWorkout {
    func toAscendWorkout(with metrics: WorkoutMetrics) -> Workout {
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
        let floors = Workout.stepsToFloors(steps)

        return Workout(
            name: Workout.generateDefaultName(for: startDate),
            date: startDate,
            duration: duration,
            steps: steps,
            floors: floors,
            stepsPerFloor: Workout.defaultStepsPerFloor,
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
