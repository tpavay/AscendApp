import Foundation

enum WeekConfiguration {
    static let mondayFirstWeekday = 2

    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = mondayFirstWeekday
        return calendar
    }

    static func shortDayName(for firstWeekday: Int = mondayFirstWeekday) -> String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let index = max(0, min(dayNames.count - 1, firstWeekday - 1))
        return dayNames[index]
    }

    static func fullDayName(for firstWeekday: Int = mondayFirstWeekday) -> String {
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let index = max(0, min(dayNames.count - 1, firstWeekday - 1))
        return dayNames[index]
    }
}
