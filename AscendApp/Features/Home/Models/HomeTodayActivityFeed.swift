import Foundation

/// The server's `home_today_activity/global` document: the most recent uploaded climbs
/// across every session kind, newest first. Home shows the first `homeRowLimit`; SEE ALL
/// shows all of them.
struct HomeTodayActivityFeed: Equatable, Sendable {
    /// How many rows Home's sheet shows before SEE ALL. Settled at three.
    static let homeRowLimit = 3

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

    /// The same feed with every row marked against the signed-in climber.
    func marking(currentUserId: String?) -> HomeTodayActivityFeed {
        HomeTodayActivityFeed(
            rows: rows.map { $0.marking(currentUserId: currentUserId) },
            updatedAt: updatedAt
        )
    }
}
