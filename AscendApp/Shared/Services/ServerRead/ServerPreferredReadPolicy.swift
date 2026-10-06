import Foundation

/// What `ServerPreferredRead` may do after the server gives no answer.
struct ServerPreferredReadPolicy: Sendable, Equatable {
    /// How long to wait before the one quiet retry. The Firestore SDK's own reconnect backoff
    /// starts at one second, so a momentarily dropped stream is usually back by then.
    var retryDelay: Duration = ServerPreferredRead.defaultRetryDelay
    /// Whether an unreachable-class failure earns the quiet retry.
    var retriesUnreachable = true
    /// Whether the device's last copy may stand in, flagged, once the server has given no answer.
    var fallsBackToCache = false

    /// The server's answer or a thrown error. For reads whose result decides a write, a rank or a
    /// "seen" flag, where a stale copy would be wrong rather than merely old.
    static let serverRequired = ServerPreferredReadPolicy()

    /// The server's answer, else the device's last copy with `isFromCache` set.
    static let cacheFallback = ServerPreferredReadPolicy(fallsBackToCache: true)
}
