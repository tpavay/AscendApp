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
    
    // Calculate the start date for this time frame
    func startDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .monthly:
            return calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .yearly:
            return calendar.dateInterval(of: .year, for: now)?.start ?? now
        case .allTime:
            return Date.distantPast
        }
    }
    
    // Get the period identifier (e.g., "2025-W40" for week 40 of 2025)
    func periodIdentifier(for date: Date = Date()) -> String {
        let calendar = Calendar.current
        
        switch self {
        case .weekly:
            let year = calendar.component(.yearForWeekOfYear, from: date)
            let week = calendar.component(.weekOfYear, from: date)
            return "\(year)-W\(String(format: "%02d", week))"
        case .monthly:
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            return "\(year)-M\(String(format: "%02d", month))"
        case .yearly:
            let year = calendar.component(.year, from: date)
            return "\(year)"
        case .allTime:
            return "all"
        }
    }
    
    // Check if stats should be reset based on time frame
    func shouldReset(lastUpdated: Date) -> Bool {
        switch self {
        case .allTime:
            return false
        case .weekly, .monthly, .yearly:
            return periodIdentifier(for: lastUpdated) != periodIdentifier()
        }
    }
}
