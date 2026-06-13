import Foundation

enum ClimbDropNotificationPreferenceStore {
    private static let isEnabledKey = "climbDropNotificationsEnabled.v1"

    static var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: isEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: isEnabledKey)
            NotificationCenter.default.post(name: .climbDropNotificationPreferenceDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let climbDropNotificationPreferenceDidChange = Notification.Name("climbDropNotificationPreferenceDidChange")
}
