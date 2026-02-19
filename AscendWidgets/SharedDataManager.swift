//
//  SharedDataManager.swift
//  AscendWidgets
//
//  Created by Claude on 2/19/26.
//

import Foundation

/// Manages shared data between the main app and widgets via App Group UserDefaults
struct SharedDataManager {
    static let appGroupIdentifier = "group.com.ascendapp.shared"
    
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
    
    // MARK: - Keys
    
    private enum Keys {
        static let currentStreak = "widget_currentStreak"
        static let weeklySteps = "widget_weeklySteps"
        static let weeklyFloors = "widget_weeklyFloors"
        static let weeklyWorkoutCount = "widget_weeklyWorkoutCount"
        static let lastWorkoutDate = "widget_lastWorkoutDate"
        static let todaySteps = "widget_todaySteps"
        static let todayFloors = "widget_todayFloors"
        static let weeklyGoalSteps = "widget_weeklyGoalSteps"
        static let lastUpdated = "widget_lastUpdated"
    }
    
    // MARK: - Widget Data Model
    
    struct WidgetData {
        let currentStreak: Int
        let weeklySteps: Int
        let weeklyFloors: Int
        let weeklyWorkoutCount: Int
        let lastWorkoutDate: Date?
        let todaySteps: Int
        let todayFloors: Int
        let weeklyGoalSteps: Int
        let lastUpdated: Date
        
        static var placeholder: WidgetData {
            WidgetData(
                currentStreak: 7,
                weeklySteps: 15000,
                weeklyFloors: 120,
                weeklyWorkoutCount: 4,
                lastWorkoutDate: Date(),
                todaySteps: 2500,
                todayFloors: 30,
                weeklyGoalSteps: 20000,
                lastUpdated: Date()
            )
        }
        
        static var empty: WidgetData {
            WidgetData(
                currentStreak: 0,
                weeklySteps: 0,
                weeklyFloors: 0,
                weeklyWorkoutCount: 0,
                lastWorkoutDate: nil,
                todaySteps: 0,
                todayFloors: 0,
                weeklyGoalSteps: 20000,
                lastUpdated: Date()
            )
        }
    }
    
    // MARK: - Read Data (Widget side)
    
    static func getWidgetData() -> WidgetData {
        guard let defaults = sharedDefaults else {
            return .empty
        }
        
        return WidgetData(
            currentStreak: defaults.integer(forKey: Keys.currentStreak),
            weeklySteps: defaults.integer(forKey: Keys.weeklySteps),
            weeklyFloors: defaults.integer(forKey: Keys.weeklyFloors),
            weeklyWorkoutCount: defaults.integer(forKey: Keys.weeklyWorkoutCount),
            lastWorkoutDate: defaults.object(forKey: Keys.lastWorkoutDate) as? Date,
            todaySteps: defaults.integer(forKey: Keys.todaySteps),
            todayFloors: defaults.integer(forKey: Keys.todayFloors),
            weeklyGoalSteps: defaults.integer(forKey: Keys.weeklyGoalSteps),
            lastUpdated: defaults.object(forKey: Keys.lastUpdated) as? Date ?? Date()
        )
    }
    
    // MARK: - Write Data (Main app side)
    
    static func updateWidgetData(
        currentStreak: Int,
        weeklySteps: Int,
        weeklyFloors: Int,
        weeklyWorkoutCount: Int,
        lastWorkoutDate: Date?,
        todaySteps: Int,
        todayFloors: Int,
        weeklyGoalSteps: Int
    ) {
        guard let defaults = sharedDefaults else { return }
        
        defaults.set(currentStreak, forKey: Keys.currentStreak)
        defaults.set(weeklySteps, forKey: Keys.weeklySteps)
        defaults.set(weeklyFloors, forKey: Keys.weeklyFloors)
        defaults.set(weeklyWorkoutCount, forKey: Keys.weeklyWorkoutCount)
        defaults.set(lastWorkoutDate, forKey: Keys.lastWorkoutDate)
        defaults.set(todaySteps, forKey: Keys.todaySteps)
        defaults.set(todayFloors, forKey: Keys.todayFloors)
        defaults.set(weeklyGoalSteps, forKey: Keys.weeklyGoalSteps)
        defaults.set(Date(), forKey: Keys.lastUpdated)
    }
}
