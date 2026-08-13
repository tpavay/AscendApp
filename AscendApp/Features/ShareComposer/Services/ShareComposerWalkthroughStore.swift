import Foundation

/// Device-local persistence for the disposable first-open walkthrough state.
struct ShareComposerWalkthroughStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasSeenWalkthrough: Bool {
        defaults.bool(forKey: ShareComposerCoachMark.seenStorageKey)
    }

    func markSeen() {
        defaults.set(true, forKey: ShareComposerCoachMark.seenStorageKey)
    }

    func reset() {
        defaults.removeObject(forKey: ShareComposerCoachMark.seenStorageKey)
    }
}
