import Foundation

/// Persists `PresetPreferences` in `UserDefaults`. The defaults instance is injected so a test
/// never touches the real store.
struct PresetPreferencesStore {
    static let key = "share.presetPrefs.v2"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PresetPreferences {
        guard let data = defaults.data(forKey: Self.key),
              let preferences = try? JSONDecoder().decode(PresetPreferences.self, from: data) else {
            return .defaults
        }
        return preferences
    }

    func save(_ preferences: PresetPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}
