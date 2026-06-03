import Foundation

enum TodayClimbNotificationPreferenceStore {
    private static let isEnabledKey = "todayClimbDropNotificationsEnabled"

    static var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: isEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: isEnabledKey)
            NotificationCenter.default.post(name: .todayClimbNotificationPreferenceDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let todayClimbNotificationPreferenceDidChange = Notification.Name("todayClimbNotificationPreferenceDidChange")
}
