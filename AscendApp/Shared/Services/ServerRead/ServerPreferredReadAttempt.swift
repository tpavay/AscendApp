import Foundation

/// Which copy `ServerPreferredRead` is asking its caller to read.
enum ServerPreferredReadAttempt: Sendable {
    /// The server's answer. Asked first, and again after a quiet retry or a healed refusal.
    case server
    /// The device's last copy, asked only when the policy allows a fallback and the server gave
    /// no answer.
    case cache
}
