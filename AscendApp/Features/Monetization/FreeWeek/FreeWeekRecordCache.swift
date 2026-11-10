import Foundation

/// The device's copy of a week it has already been told about, keyed by account.
///
/// A running week has to open the app on a cold launch with no network, exactly as a paid
/// entitlement RevenueCat cached does. Only a grant is ever stored: the absence of a record is
/// re-read every launch, because a week started on another device must not be hidden by a stale
/// "none". Account deletion clears the whole defaults domain, this with it.
struct FreeWeekRecordCache {
    private struct Entry: Codable {
        var grant: FreeWeekGrant
        var didReportExpiredGate = false
        /// Which onboarding the climber came through when this device started the week. The pass
        /// that knew it is complete, and forgotten, by the time the week ends or converts.
        var flowVersion: String?
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func grant(for userID: String) -> FreeWeekGrant? {
        entry(for: userID)?.grant
    }

    func store(_ grant: FreeWeekGrant, for userID: String) {
        var entry = entry(for: userID) ?? Entry(grant: grant)
        entry.grant = grant
        save(entry, for: userID)
    }

    func flowVersion(for userID: String) -> String? {
        entry(for: userID)?.flowVersion
    }

    func storeFlowVersion(_ flowVersion: String, for userID: String) {
        guard var entry = entry(for: userID) else { return }
        entry.flowVersion = flowVersion
        save(entry, for: userID)
    }

    /// Marks the "week ended, gate shown" report as sent, returning whether this call is the one
    /// that sent it. The gate opens on every launch of a climber whose week is over, and the event
    /// counts climbers, not launches.
    func claimExpiredGateReport(for userID: String) -> Bool {
        guard var entry = entry(for: userID), !entry.didReportExpiredGate else { return false }
        entry.didReportExpiredGate = true
        save(entry, for: userID)
        return true
    }

    private func entry(for userID: String) -> Entry? {
        guard let data = userDefaults.data(forKey: Self.key(for: userID)) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    private func save(_ entry: Entry, for userID: String) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        userDefaults.set(data, forKey: Self.key(for: userID))
    }

    private static func key(for userID: String) -> String {
        "monetization.freeWeek.record.\(userID)"
    }
}
