import Foundation
import Testing
@testable import AscendApp

struct IgnoredAppleHealthWorkoutStoreTests {
    @Test
    func insertTracksIgnoredExternalRecordIDsUniquely() {
        let defaults = makeDefaults()
        let store = IgnoredAppleHealthWorkoutStore(defaults: defaults, key: "ignored")

        store.insert("ah_1")
        store.insert("ah_2")
        store.insert("ah_1")

        #expect(store.load() == Set(["ah_1", "ah_2"]))
    }

    @Test
    func pruneDropsExternalRecordIDsThatNoLongerExist() {
        let defaults = makeDefaults()
        let store = IgnoredAppleHealthWorkoutStore(defaults: defaults, key: "ignored")

        store.insert("ah_keep")
        store.insert("ah_drop")
        store.prune(validExternalRecordIDs: Set(["ah_keep"]))

        #expect(store.load() == Set(["ah_keep"]))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "IgnoredAppleHealthWorkoutStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
