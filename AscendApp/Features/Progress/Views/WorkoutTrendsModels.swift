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

/// A bucketed aggregate for trends (weekly or monthly).
struct WorkoutTrendBucket: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let totalMetric: Double
    let metricPerMinute: Double
    let averageHeartRate: Double?
    let workoutCount: Int
}

/// The kinds of trend metrics we plot for workouts.
enum WorkoutTrendMetricType: String, Identifiable {
    case preferredTotal
    case preferredPerMinute
    case averageHeartRate
    
    var id: String { rawValue }
    
    func title(using preferredMetric: WorkoutMetric) -> String {
        switch self {
        case .preferredTotal:
            return preferredMetric.displayName
        case .preferredPerMinute:
            return "\(preferredMetric.displayName) per Minute"
        case .averageHeartRate:
            return "Average Heart Rate"
        }
    }
    
    func unit(using preferredMetric: WorkoutMetric) -> String {
        switch self {
        case .preferredTotal:
            return preferredMetric.unit
        case .preferredPerMinute:
            return "\(preferredMetric.unit)/min"
        case .averageHeartRate:
            return "bpm"
        }
    }
    
    func value(for workout: Workout, preferredMetric: WorkoutMetric) -> Double? {
        switch self {
        case .preferredTotal:
            return Double(workout.metricValue(for: preferredMetric))
        case .preferredPerMinute:
            return workout.pace(for: preferredMetric)
        case .averageHeartRate:
            guard let avg = workout.avgHeartRate else { return nil }
            return Double(avg)
        }
    }
}

struct WorkoutTrendsBuilder {
    static func trendPoints(
        from workouts: [Workout],
        metric: WorkoutTrendMetricType,
        preferredMetric: WorkoutMetric
    ) -> [WorkoutTrendPoint] {
        workouts
            .compactMap { workout in
                guard let value = metric.value(for: workout, preferredMetric: preferredMetric) else { return nil }
                return WorkoutTrendPoint(date: workout.date, value: value, workout: workout)
            }
            .sorted { $0.date < $1.date }
    }
    
    static func trendBuckets(
        from workouts: [Workout],
        preferredMetric: WorkoutMetric,
        range: WorkoutTrendRange,
        calendar: Calendar,
        anchor: Date = Date()
    ) -> [WorkoutTrendBucket] {
        guard let interval = range.dateInterval(using: calendar, anchor: anchor) else { return [] }
        guard range.bucketStyle != .perWorkout else { return [] }
        
        let bucketStyle = range.bucketStyle
        let bucketStart = bucketStyle == .week
            ? startOfWeek(for: interval.start, calendar: calendar)
            : startOfMonth(for: interval.start, calendar: calendar)
        
        var buckets: [WorkoutTrendBucket] = []
        var cursor = bucketStart
        
        while cursor < interval.end {
            let next: Date
            switch bucketStyle {
            case .week:
                next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? interval.end
            case .month:
                next = calendar.date(byAdding: .month, value: 1, to: cursor) ?? interval.end
            case .perWorkout:
                // Not used for per-workout; guard against misuse.
                next = interval.end
            }
            
            let bucketWorkouts = workouts.filter { $0.date >= cursor && $0.date < next }
            let totalMetric = bucketWorkouts.reduce(0.0) { $0 + Double($1.metricValue(for: preferredMetric)) }
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
                workoutCount: bucketWorkouts.count
            ))
            
            cursor = next
        }
        
        return buckets
    }
    
    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }
    
    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}
