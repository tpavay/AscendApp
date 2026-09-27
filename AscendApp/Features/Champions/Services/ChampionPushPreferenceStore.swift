import Foundation

/// Whether the climber wants a push when they take a crown. On unless they turn it off:
/// the alert is about their own win, so it is opt-out, and the server treats an absent
/// preference the same way.
enum ChampionPushPreferenceStore {
    private static let isEnabledKey = "championPushEnabled.v1"

    static var isEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: isEnabledKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: isEnabledKey)
        }
    }
}
