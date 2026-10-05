import Foundation

/// How loudly a recorded non-fatal should read in the diagnostics that carry a level.
///
/// Sentry is the one that does. Every non-fatal used to arrive at `error`, so a dropped stream
/// that recovered on its own would have sat in production's issue list beside a real defect.
enum TelemetryErrorSeverity: String, Sendable {
    /// Worth counting, not worth being paged about: it is expected to clear on its own.
    case warning
    /// Somebody has to read this one.
    case error
}
