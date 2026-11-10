import Foundation

/// The one line Settings says about a running free week.
enum FreeWeekSettingsRow {
    /// `nil` when no week is running, so the row is simply not there.
    static func title(daysLeft: Int?) -> String? {
        guard let daysLeft, daysLeft > 0 else { return nil }
        return daysLeft == 1 ? "Free trial, 1 day left" : "Free trial, \(daysLeft) days left"
    }
}
