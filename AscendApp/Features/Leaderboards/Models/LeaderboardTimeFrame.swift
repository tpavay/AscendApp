//
//  LeaderboardTimeFrame.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation

enum LeaderboardTimeFrame: String, CaseIterable, Codable, Identifiable {
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"
    case allTime = "all_time"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        case .allTime:
            return "All Time"
        }
    }
    
    var shortName: String {
        switch self {
        case .weekly:
            return "Week"
        case .monthly:
            return "Month"
        case .yearly:
            return "Year"
        case .allTime:
            return "All"
        }
    }
    
    private func configuredCalendar(firstWeekday: Int? = nil, timeZone: TimeZone? = nil) -> Calendar {
        var calendar = Calendar.current
        if let firstWeekday {
            calendar.firstWeekday = firstWeekday
        }
        if let timeZone {
            calendar.timeZone = timeZone
        }
        return calendar
    }

    // Calculate the start date for this time frame
    func startDate(
        for date: Date = Date(),
        firstWeekday: Int? = nil,
        timeZone: TimeZone? = nil
    ) -> Date {
        let calendar = configuredCalendar(firstWeekday: firstWeekday, timeZone: timeZone)

        switch self {
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        case .monthly:
            return calendar.dateInterval(of: .month, for: date)?.start ?? date
        case .yearly:
            return calendar.dateInterval(of: .year, for: date)?.start ?? date
        case .allTime:
            return Date.distantPast
        }
    }
    
    // Get the period identifier (e.g., "2025-W40" for week 40 of 2025)
    func periodIdentifier(
        for date: Date = Date(),
        firstWeekday: Int? = nil,
        timeZone: TimeZone? = nil
    ) -> String {
        let calendar = configuredCalendar(firstWeekday: firstWeekday, timeZone: timeZone)
        
        switch self {
        case .weekly:
            let year = calendar.component(.yearForWeekOfYear, from: date)
            let week = calendar.component(.weekOfYear, from: date)
            return "\(year)-W\(week < 10 ? "0" : "")\(week)"
        case .monthly:
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            return "\(year)-M\(month < 10 ? "0" : "")\(month)"
        case .yearly:
            let year = calendar.component(.year, from: date)
            return "\(year)"
        case .allTime:
            return "all"
        }
    }
    
    // Check if stats should be reset based on time frame
    func shouldReset(
        lastUpdated: Date,
        referenceDate: Date = Date(),
        firstWeekday: Int? = nil,
        timeZone: TimeZone? = nil
    ) -> Bool {
        switch self {
        case .allTime:
            return false
        case .weekly, .monthly, .yearly:
            return periodIdentifier(for: lastUpdated, firstWeekday: firstWeekday, timeZone: timeZone)
            != periodIdentifier(for: referenceDate, firstWeekday: firstWeekday, timeZone: timeZone)
        }
    }

    // MARK: - Reset Info

    func nextResetDate(from date: Date = Date()) -> Date? {
        let calendar = Calendar.current

        switch self {
        case .allTime:
            return nil
        case .weekly:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: date),
                  let next = calendar.date(byAdding: .weekOfYear, value: 1, to: interval.start) else {
                return nil
            }
            return next
        case .monthly:
            guard let interval = calendar.dateInterval(of: .month, for: date),
                  let next = calendar.date(byAdding: .month, value: 1, to: interval.start) else {
                return nil
            }
            return next
        case .yearly:
            guard let interval = calendar.dateInterval(of: .year, for: date),
                  let next = calendar.date(byAdding: .year, value: 1, to: interval.start) else {
                return nil
            }
            return next
        }
    }

    func daysUntilReset(from date: Date = Date()) -> Int? {
        guard let resetDate = nextResetDate(from: date) else { return nil }
        let interval = resetDate.timeIntervalSince(date)
        if interval <= 0 { return 0 }
        return Int(ceil(interval / 86_400))
    }

    func resetDescription(from date: Date = Date()) -> String {
        guard let resetDate = nextResetDate(from: date) else {
            return "This leaderboard never resets"
        }

        let interval = resetDate.timeIntervalSince(date)
        if interval <= 0 {
            return "Leaderboard resets in less than a day"
        }

        if interval < 86_400 {
            return "Leaderboard resets in less than a day"
        }

        let days = Int(ceil(interval / 86_400))
        let unit = days == 1 ? "day" : "days"
        return "Leaderboard resets in \(days) \(unit)"
    }
}
