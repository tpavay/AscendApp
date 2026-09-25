import Foundation
@preconcurrency import FirebaseFirestore

/// Reads Home's ON THE GLOBE TODAY feed.
///
/// The feed is one server-owned document, so the client holds one listener on it and
/// never writes it (`firestore.rules`: `home_today_activity`, `allow write: if false`).
protocol HomeTodayActivityServicing: Sendable {
    /// Every version of the feed the server publishes while the stream is consumed.
    /// The listener is removed when the consuming task is cancelled.
    func feedUpdates() -> AsyncStream<HomeTodayActivityFeed>
}

final class FirestoreHomeTodayActivityService: HomeTodayActivityServicing, @unchecked Sendable {
    static let shared = FirestoreHomeTodayActivityService()

    private let db = Firestore.firestore()

    private init() {}

    func feedUpdates() -> AsyncStream<HomeTodayActivityFeed> {
        let document = db.collection("home_today_activity").document("global")
        return AsyncStream { continuation in
            let registration = document.addSnapshotListener { snapshot, error in
                if let error {
                    // A failed read is not an empty feed. Keep whatever the reader already
                    // holds and let the next snapshot replace it.
                    debugLog("Home today feed listener failed: \(error)")
                    return
                }
                continuation.yield(HomeTodayActivityFeedDecoder.feed(from: snapshot?.data()))
            }
            continuation.onTermination = { _ in
                registration.remove()
            }
        }
    }
}
