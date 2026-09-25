import Foundation
import Observation

/// Holds Home's ON THE GLOBE TODAY feed for as long as Home is mounted.
///
/// One listener on the server's one document. The stream is consumed by a task the
/// view owns, so the listener dies with the Home tab; hidden tabs are unmounted and
/// must run nothing. Rows reach views only after `ModerationStore` has resolved them.
///
/// The server prunes rows published more than a day ago only when it rewrites the
/// document, so on a quiet day the stored rows outlive the header's promise. The
/// rows exposed here are re-cut against the same day bound on a clock the view
/// advances, so nothing days old ever sits under ON THE GLOBE TODAY.
@MainActor
@Observable
final class HomeTodayActivityViewModel {
    private(set) var feed: HomeTodayActivityFeed = .empty
    private(set) var hasReceivedFeed = false
    /// The moment the day bound is measured from. Advanced by `tick`.
    private(set) var clock: Date

    private let service: any HomeTodayActivityServicing
    private var currentUserId: String?

    init(
        service: any HomeTodayActivityServicing = FirestoreHomeTodayActivityService.shared,
        now: Date = Date()
    ) {
        self.service = service
        self.clock = now
    }

    /// Moves the day bound forward. The view calls it on its minute cadence so a row
    /// that ages out between snapshots leaves the section without a server rewrite.
    func tick(now: Date = Date()) {
        clock = now
    }

    /// The feed cut to rows published within the last day.
    var visibleFeed: HomeTodayActivityFeed {
        feed.keepingRows(publishedWithin: HomeTodayActivityFeed.maxRowAge, of: clock)
    }

    /// Consumes feed updates until the calling task is cancelled.
    func observe(currentUserId: String?) async {
        self.currentUserId = currentUserId
        for await update in service.feedUpdates() {
            guard !Task.isCancelled else { return }
            feed = update.marking(currentUserId: self.currentUserId)
            clock = Date()
            hasReceivedFeed = true
        }
    }

    var homeRows: [HomeTodayActivityRow] {
        visibleFeed.homeRows
    }

    var allRows: [HomeTodayActivityRow] {
        visibleFeed.rows
    }

    var showsSeeAll: Bool {
        visibleFeed.hasMoreThanHomeRows
    }
}
