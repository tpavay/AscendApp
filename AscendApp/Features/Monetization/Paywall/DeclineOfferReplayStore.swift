import Foundation

/// What the device remembers so a climber who force-closes the app on the first paywall still meets
/// the decline offer (the gift screen) on the next launch.
///
/// The offer is Superwall's: the SDK opens it when the first paywall is closed, so a climber who
/// kills the app first never reaches it. Two facts per account carry the rest:
///
/// - **Pending**: the first paywall reached the screen and the offer has not been seen since. Set
///   when the paywall is presented, cleared when the offer is shown or access arrives.
/// - **Shown**: the offer has reached this account's screen, by the SDK's chain or by the replay.
///   Never cleared, so no later launch can show it again.
///
/// Both are keyed by the Firebase uid, so one account's marker never lands on the next account to
/// sign in on the phone. Local only; the uid is the only thing stored.
struct DeclineOfferReplayStore: @unchecked Sendable {
    static let pendingKey = "appAccessGate.declineOfferPending"
    static let shownKey = "appAccessGate.declineOfferShown"
    /// A phone holds a handful of accounts at most; the cap keeps the list from growing for ever.
    static let shownCapacity = 16

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func pendingUserID() -> String? {
        userDefaults.string(forKey: Self.pendingKey)
    }

    func hasShown(for userID: String) -> Bool {
        shownUserIDs().contains(userID)
    }

    /// The first paywall is on screen. Does nothing for an account that has already seen the offer,
    /// which is what keeps a replayed offer from being owed again.
    func markPending(for userID: String) {
        guard !hasShown(for: userID) else { return }
        userDefaults.set(userID, forKey: Self.pendingKey)
    }

    /// The offer reached the screen, so it is no longer owed and never will be again.
    func markShown(for userID: String) {
        var shown = shownUserIDs().filter { $0 != userID }
        shown.append(userID)
        userDefaults.set(Array(shown.suffix(Self.shownCapacity)), forKey: Self.shownKey)
        clearPending()
    }

    func clearPending() {
        userDefaults.removeObject(forKey: Self.pendingKey)
    }

    private func shownUserIDs() -> [String] {
        userDefaults.stringArray(forKey: Self.shownKey) ?? []
    }
}
