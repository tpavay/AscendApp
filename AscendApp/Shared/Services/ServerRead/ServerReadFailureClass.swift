import Foundation
import FirebaseFirestore

/// Why a read that wanted the server's answer did not get one.
///
/// Three classes, because they need three different responses and used to share one: a server
/// that could not be reached (wait and ask again), a server that answered no (re-derive access),
/// and everything else (a defect somebody has to read about). One catch-all sentence covered a
/// production rules outage on 2026-09-25 and a five-minute dropped stream on 2026-10-03, and
/// nobody could tell them apart from the phone.
enum ServerReadFailureClass: String, Sendable, CaseIterable {
    /// The request never got a server answer: the SDK's stream is down, the call timed out, or
    /// the transport failed. Usually clears on its own within seconds.
    case unreachable
    /// The server answered and refused: rules denied the read or the session is not signed in.
    case refused
    /// Anything else, a missing index included. Never expected in a healthy build.
    case unexpected

    /// The Firestore codes that mean "no server answer", from the pinned SDK (11.15.0).
    ///
    /// `unavailable` is the one a forced read gets the moment the SDK marks itself offline, which
    /// takes a single failed stream attempt (`online_state_tracker.cc`, `kMaxWatchStreamFailures`).
    private static let unreachableFirestoreCodes: Set<Int> = [
        FirestoreErrorCode.unavailable.rawValue,
        FirestoreErrorCode.deadlineExceeded.rawValue,
        FirestoreErrorCode.cancelled.rawValue,
        FirestoreErrorCode.internal.rawValue
    ]

    private static let refusedFirestoreCodes: Set<Int> = [
        FirestoreErrorCode.permissionDenied.rawValue,
        FirestoreErrorCode.unauthenticated.rawValue
    ]

    static func classify(_ error: any Error) -> ServerReadFailureClass {
        if error is CancellationError || error is any ServerReadTimeoutError {
            return .unreachable
        }

        let nsError = error as NSError
        switch nsError.domain {
        case FirestoreErrorDomain:
            if unreachableFirestoreCodes.contains(nsError.code) { return .unreachable }
            if refusedFirestoreCodes.contains(nsError.code) { return .refused }
            return .unexpected
        case NSURLErrorDomain:
            return .unreachable
        default:
            return .unexpected
        }
    }
}
