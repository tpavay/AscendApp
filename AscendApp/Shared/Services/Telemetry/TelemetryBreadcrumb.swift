import Foundation

/// A leveled trail entry for the crash reporters: what the app was doing before the event that
/// gets reported. Sentry keeps the level and the data; Crashlytics keeps one log line.
///
/// `AppDiagnosticsRecorder` warnings and errors travel as these, so a lost session's trail - the
/// memory warnings, the refused checkpoint, the recovery that followed - is on the next Sentry
/// event rather than in a Crashlytics log that ships only with a crash.
struct TelemetryBreadcrumb: Equatable, Sendable {
    enum Level: String, Sendable {
        case info
        case warning
        case error
    }

    let category: String
    let message: String
    let level: Level
    let data: [String: String]

    init(category: String, message: String, level: Level, data: [String: String] = [:]) {
        self.category = category
        self.message = message
        self.level = level
        self.data = data
    }

    /// One line carrying the level, for a reporter that keeps breadcrumbs as plain log lines.
    var logLine: String {
        level == .info ? message : "[\(level.rawValue)] \(message)"
    }
}
