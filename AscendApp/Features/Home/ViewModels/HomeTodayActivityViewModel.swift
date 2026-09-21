import Foundation
import Observation

/// Holds Home's ON THE GLOBE TODAY feed for as long as Home is mounted.
///
/// One listener on the server's one document. The stream is consumed by a task the
/// view owns, so the listener dies with the Home tab; hidden tabs are unmounted and
/// must run nothing. Rows reach views only after `ModerationStore` has resolved them.
@MainActor
@Observable
final class HomeTodayActivityViewModel {
    private(set) var feed: HomeTodayActivityFeed = .empty
    private(set) var hasReceivedFeed = false

    private let service: any HomeTodayActivityServicing
    private var currentUserId: String?

    init(service: any HomeTodayActivityServicing = FirestoreHomeTodayActivityService.shared) {
        self.service = service
    }

    /// Consumes feed updates until the calling task is cancelled.
    func observe(currentUserId: String?) async {
        self.currentUserId = currentUserId
        for await update in service.feedUpdates() {
            guard !Task.isCancelled else { return }
            feed = update.marking(currentUserId: self.currentUserId)
            hasReceivedFeed = true
        }
    }

    var homeRows: [HomeTodayActivityRow] {
        feed.homeRows
    }

    var allRows: [HomeTodayActivityRow] {
        feed.rows
    }

    var showsSeeAll: Bool {
        feed.hasMoreThanHomeRows
    }
}
