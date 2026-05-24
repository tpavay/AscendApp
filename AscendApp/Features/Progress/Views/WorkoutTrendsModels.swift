//
//  WorkoutTrendsModels.swift
//  AscendApp
//
//  Created by ChatGPT on 5/25/24.
//

import Foundation

/// A point on a workout trend chart (per workout, not aggregated by day).
struct WorkoutTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let workout: Workout
}

/// A bucketed aggregate for trends (monthly).
struct WorkoutTrendBucket: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let totalMetric: Double
    let metricPerMinute: Double
    let averageHeartRate: Double?
    let workoutCount: Int
    let totalDuration: TimeInterval
}

/// The kinds of trend metrics we plot for workouts.
enum WorkoutTrendMetricType: String, Identifiable {
    case stepsTotal
    case stepsPerMinute
    case averageHeartRate
    case duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stepsTotal:
            return "Steps"
        case .stepsPerMinute:
            return "Steps per Minute"
        case .averageHeartRate:
            return "Average Heart Rate"
        case .duration:
            return "Duration"
        }
    }

    var unit: String {
        switch self {
        case .stepsTotal:
            return "steps"
        case .stepsPerMinute:
            return "steps/min"
        case .averageHeartRate:
            return "bpm"
        case .duration:
            return "min"
        }
    }

    func value(for workout: Workout) -> Double? {
        switch self {
        case .stepsTotal:
            return Double(workout.steps)
        case .stepsPerMinute:
            return workout.stepsPerMinute
        case .averageHeartRate:
            guard let avg = workout.avgHeartRate else { return nil }
            return Double(avg)
        case .duration:
            return workout.duration / 60.0 // Return minutes
        }
    }
}

struct WorkoutTrendsBuilder {
    static func trendPoints(
        from workouts: [Workout],
        metric: WorkoutTrendMetricType
    ) -> [WorkoutTrendPoint] {
        workouts
            .compactMap { workout in
                guard let value = metric.value(for: workout) else { return nil }
                return WorkoutTrendPoint(date: workout.date, value: value, workout: workout)
            }
            .sorted { $0.date < $1.date }
    }
    
    static func trendBuckets(
        from workouts: [Workout],
        range: WorkoutTrendRange,
        calendar: Calendar,
        anchor: Date = Date()
    ) -> [WorkoutTrendBucket] {
        guard let interval = range.dateInterval(using: calendar, anchor: anchor) else { return [] }
        guard range.bucketStyle == .month else { return [] }

        let bucketStart = startOfMonth(for: interval.start, calendar: calendar)

        var buckets: [WorkoutTrendBucket] = []
        var cursor = bucketStart

        while cursor < interval.end {
            let next = calendar.date(byAdding: .month, value: 1, to: cursor) ?? interval.end

            let bucketWorkouts = workouts.filter { $0.date >= cursor && $0.date < next }
            let totalMetric = bucketWorkouts.reduce(0.0) { $0 + Double($1.steps) }
            let totalDuration = bucketWorkouts.reduce(0.0) { $0 + $1.duration }
            let minutes = totalDuration / 60.0
            let metricPerMinute = minutes > 0 ? totalMetric / minutes : 0

            let heartRates = bucketWorkouts.compactMap(\.avgHeartRate).map(Double.init)
            let averageHeartRate = heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count)

            buckets.append(WorkoutTrendBucket(
                startDate: cursor,
                endDate: next,
                totalMetric: totalMetric,
                metricPerMinute: metricPerMinute,
                averageHeartRate: averageHeartRate,
                workoutCount: bucketWorkouts.count,
                totalDuration: totalDuration
            ))

            cursor = next
        }

        return buckets
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}
