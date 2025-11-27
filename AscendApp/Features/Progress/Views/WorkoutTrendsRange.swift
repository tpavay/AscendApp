//
//  WorkoutTrendsRange.swift
//  AscendApp
//
//  Created by ChatGPT on 5/26/24.
//

import Foundation

enum TrendBucketStyle {
    case perWorkout
    case week
    case month
}

enum WorkoutTrendRange: String, CaseIterable, Identifiable {
    case thisWeek
    case thisMonth
    case lastSixMonths
    case lastYear
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .lastSixMonths: return "Last 6 Months"
        case .lastYear: return "Last Year"
        }
    }
    
    var shortTitle: String {
        switch self {
        case .thisWeek: return "W"
        case .thisMonth: return "M"
        case .lastSixMonths: return "6M"
        case .lastYear: return "Y"
        }
    }
    
    var bucketStyle: TrendBucketStyle {
        switch self {
        case .thisWeek, .thisMonth:
            return .perWorkout
        case .lastSixMonths:
            return .week
        case .lastYear:
            return .month
        }
    }
    
    func dateInterval(using calendar: Calendar, anchor: Date = Date()) -> DateInterval? {
        switch self {
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: anchor)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: anchor)
        case .lastSixMonths:
            guard let start = calendar.date(byAdding: .month, value: -5, to: startOfMonth(for: anchor, calendar: calendar)),
                  let end = calendar.date(byAdding: .month, value: 1, to: startOfMonth(for: anchor, calendar: calendar)) else { return nil }
            return DateInterval(start: start, end: end)
        case .lastYear:
            // Show full calendar year containing the anchor
            let year = calendar.component(.year, from: anchor)
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }
            return DateInterval(start: start, end: end)
        }
    }
    
    private func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}

enum WorkoutTrendBucketValueType {
    case total
    case perMinute
    case averageHeartRate
}
