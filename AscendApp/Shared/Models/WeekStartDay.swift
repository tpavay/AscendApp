//
//  WeekStartDay.swift
//  AscendApp
//

import Foundation

enum WeekStartDay: String, CaseIterable, Codable, Identifiable {
    case sunday
    case monday

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sunday:
            return "Sunday"
        case .monday:
            return "Monday"
        }
    }

    /// Calendar-compatible first weekday where 1 = Sunday, 2 = Monday.
    var firstWeekday: Int {
        switch self {
        case .sunday:
            return 1
        case .monday:
            return 2
        }
    }

    static func from(firstWeekday: Int) -> WeekStartDay {
        firstWeekday == 2 ? .monday : .sunday
    }
}
