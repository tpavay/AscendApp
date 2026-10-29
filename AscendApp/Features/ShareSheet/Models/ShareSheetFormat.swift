import Foundation

/// Number and time formatting shared by every share surface.
enum ShareSheetFormat {
    /// `1:02:50` or `9:00`.
    static func clock(_ totalSeconds: Int) -> String {
        let seconds = max(totalSeconds, 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", rest))"
        }
        return "\(minutes):\(String(format: "%02d", rest))"
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func decimal(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(places)))
    }

    /// `OCT 9`.
    static func cardDate(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).uppercased()
    }
}
