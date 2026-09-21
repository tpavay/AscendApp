import Foundation

/// The server's `home_today_activity/global` document: the most recent uploaded climbs
/// across every session kind, newest first. Home shows the first `homeRowLimit`; SEE ALL
/// shows all of them.
struct HomeTodayActivityFeed: Equatable, Sendable {
    /// How many rows Home's sheet shows before SEE ALL. Settled at three.
    static let homeRowLimit = 3
    /// How long a row stays under ON THE GLOBE TODAY, measured from when the server
    /// first saw the workout. The same day the server publishes and prunes on
    /// (`HOME_TODAY_ACTIVITY_MAX_ROW_AGE_MILLIS`).
    static let maxRowAge: TimeInterval = 24 * 60 * 60

    let rows: [HomeTodayActivityRow]
    let updatedAt: Date?

    init(rows: [HomeTodayActivityRow], updatedAt: Date?) {
        self.rows = rows
        self.updatedAt = updatedAt
    }

    static let empty = HomeTodayActivityFeed(rows: [], updatedAt: nil)

    var homeRows: [HomeTodayActivityRow] {
        Array(rows.prefix(Self.homeRowLimit))
    }

    var hasMoreThanHomeRows: Bool {
        rows.count > Self.homeRowLimit
    }

    /// The same feed without the rows published more than `maxAge` before `now`.
    /// Order is preserved, so the first rows are still the newest.
    func keepingRows(publishedWithin maxAge: TimeInterval, of now: Date) -> HomeTodayActivityFeed {
        HomeTodayActivityFeed(
            rows: rows.filter { now.timeIntervalSince($0.publishedAt) <= maxAge },
            updatedAt: updatedAt
        )
    }

    /// The same feed with every row marked against the signed-in climber.
    func marking(currentUserId: String?) -> HomeTodayActivityFeed {
        HomeTodayActivityFeed(
            rows: rows.map { $0.marking(currentUserId: currentUserId) },
            updatedAt: updatedAt
        )
    }
}
