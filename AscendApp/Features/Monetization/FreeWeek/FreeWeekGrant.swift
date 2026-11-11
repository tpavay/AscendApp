import Foundation

/// The free week on the house: seven days of app access the server gives a climber who declined
/// every paid offer, with no Apple purchase behind it (`docs/free-week-after-decline.md`).
///
/// This is the device's copy of `users/{uid}/trial/free_week`. The server decides both dates; the
/// device only ever reads them.
struct FreeWeekGrant: Codable, Equatable, Sendable {
    let grantedAt: Date
    let expiresAt: Date

    func isLive(at now: Date) -> Bool {
        expiresAt > now
    }

    /// Whole days left, rounded up, so the last partial day still reads as a day and a running
    /// week never reads as zero.
    func daysLeft(at now: Date) -> Int {
        let remaining = expiresAt.timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        return max(1, Int((remaining / 86_400).rounded(.up)))
    }
}

/// What the device knows about this account's free week record.
enum FreeWeekRecordState: Equatable, Sendable {
    /// Nothing has answered yet.
    case unknown
    /// The server answered and there is no record: this account has never had its week.
    case absent
    /// The account was given a week. Whether it is still running is a question for the clock.
    case granted(FreeWeekGrant)
    /// The server could not be asked. Deliberately not ``absent``: an account that already spent
    /// its week must not be shown the letter again off a failed read.
    case unavailable
}

/// What the app root needs from the free week, already resolved.
enum FreeWeekRoutingAccess: Equatable, Sendable {
    /// A week is running. Entry is exactly a paid climber's.
    case live
    /// The switch is on and this account's record has not been read yet, so the app cannot tell a
    /// climber on their week from a climber with no access.
    case unresolved
    /// No week is running, or the feature is off.
    case none
}
