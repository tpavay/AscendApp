import Foundation

/// Glanceable number formatting for the week summaries on Home.
enum WeekActivityFormat {
    /// "25.4h" rather than "25h 25m", "48m" under an hour.
    static func compactDuration(_ duration: TimeInterval) -> String {
        let totalHours = duration / 3600
        if totalHours >= 1 {
            let rounded = (totalHours * 10).rounded() / 10
            if rounded == rounded.rounded() {
                return "\(Int(rounded))h"
            }
            return "\(rounded.formatted(.number.precision(.fractionLength(1))))h"
        }
        return "\(Int(duration / 60))m"
    }

    /// "107.5k" rather than "107,500"; whole numbers below a thousand.
    static func compactValue(_ value: Int) -> String {
        if value >= 1000 {
            let thousands = Double(value) / 1000.0
            let rounded = (thousands * 10).rounded() / 10
            if rounded == rounded.rounded() {
                return "\(Int(rounded))k"
            }
            return "\(rounded.formatted(.number.precision(.fractionLength(1))))k"
        }
        return "\(value)"
    }
}
