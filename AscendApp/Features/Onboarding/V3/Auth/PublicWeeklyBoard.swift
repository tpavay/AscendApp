import Foundation

/// The three climbers on top of this week's Steps board, as the signed-out sign-in screen shows
/// them.
///
/// It is read from `public_weekly_steps_top/current`, which the server derives from the same rows
/// the member board ranks and which carries no uid. Nothing here is trusted as a rendering input:
/// ``moderatedEntries`` passes every row through the shared identity resolver, so a name or photo
/// crosses the same boundary it crosses on the Leaderboards tab.
struct PublicWeeklyBoard: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let rank: Int
        let displayName: String
        let photoURL: URL?
        let totalSteps: Int
    }

    static let documentSchemaVersion = 1
    static let rowLimit = 3

    let periodKey: String
    let rows: [Row]

    /// Reads the stored document, or `nil` when it cannot honestly be shown now.
    ///
    /// A document for a week that has ended is stale, not wrong: the server rewrites it within
    /// ten minutes of the Monday rollover, and until then last week's top three must not be
    /// presented under this week's countdown. The week is derived here with the same
    /// `LeaderboardTimeFrame` every board uses, so there is one definition of "this week".
    static func parse(_ data: [String: Any], now: Date) -> PublicWeeklyBoard? {
        guard (data["schemaVersion"] as? Int) == documentSchemaVersion,
              let periodKey = data["periodKey"] as? String,
              periodKey == LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: now).key,
              let storedRows = data["rows"] as? [[String: Any]] else {
            return nil
        }

        let rows = storedRows.compactMap { stored -> Row? in
            guard let rank = intValue(stored["rank"]), rank >= 1,
                  let displayName = (stored["displayName"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !displayName.isEmpty,
                  let totalSteps = intValue(stored["totalSteps"]), totalSteps > 0 else {
                return nil
            }

            let photoURL = (stored["photoURL"] as? String)
                .flatMap { $0.isEmpty ? nil : URL(string: $0) }
            return Row(rank: rank, displayName: displayName, photoURL: photoURL, totalSteps: totalSteps)
        }

        return PublicWeeklyBoard(periodKey: periodKey, rows: Array(rows.prefix(rowLimit)))
    }

    /// The rows as moderated render models. There is no block list for a climber who has no
    /// account yet, so it is hydrated and empty - the resolver still screens the name and bounds
    /// the photo URL.
    func moderatedEntries() -> [ModeratedLeaderboardEntry] {
        rows.enumerated().map { index, row in
            CrossUserIdentityAdapter.leaderboardEntry(
                LeaderboardEntry(
                    userId: "public-weekly-steps-top-\(index)",
                    displayName: row.displayName,
                    photoURL: row.photoURL,
                    rank: row.rank,
                    value: Double(row.totalSteps),
                    formattedValue: row.totalSteps.formatted()
                ),
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
