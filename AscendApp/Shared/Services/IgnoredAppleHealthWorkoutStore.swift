import Foundation

struct IgnoredAppleHealthWorkoutStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "workoutImport.ignoredAppleHealthExternalRecordIDs"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func contains(_ externalRecordID: String) -> Bool {
        load().contains(externalRecordID)
    }

    func insert(_ externalRecordID: String) {
        var ignoredIDs = load()
        let inserted = ignoredIDs.insert(externalRecordID).inserted
        guard inserted else { return }
        save(ignoredIDs)
    }

    func prune(validExternalRecordIDs: Set<String>) {
        let prunedIDs = load().intersection(validExternalRecordIDs)
        save(prunedIDs)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func save(_ ignoredIDs: Set<String>) {
        defaults.set(Array(ignoredIDs).sorted(), forKey: key)
    }
}
