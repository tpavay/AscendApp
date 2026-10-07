import Foundation

/// One leaderboard load that did not get the server's standings on the first ask.
///
/// This path used to record nothing, so two incidents with opposite causes left no device-side
/// trace of the error behind either. Every failed load now produces one of these - including the
/// ones a quiet retry recovered, because how often the stream drops is the number that says
/// whether the retry is earning its keep.
struct LeaderboardRefreshFailure: Sendable, Equatable {
    /// What the climber ended up looking at.
    enum Resolution: String, Sendable, CaseIterable {
        /// The server answered on a later attempt. Nothing was shown.
        case recovered
        /// An older copy of the board is on screen under a line saying it is not current.
        case staleBoard = "stale_board"
        /// There was no copy to show.
        case emptyBoard = "empty_board"
    }

    static let errorCode = "leaderboard_refresh_failed"

    /// The class of the last failed attempt: the one that decided what was shown, or the one a
    /// recovery followed.
    let failureClass: ServerReadFailureClass
    let errorDomain: String
    let errorCode: Int
    /// Whether the climber pulled to refresh, which is the only read that insists on the server.
    let wasForced: Bool
    let failedAttemptCount: Int
    let attemptedAccessRecovery: Bool
    let resolution: Resolution
    let context: ServerReadFailureContext

    init(
        lastFailure: ServerReadFailure,
        failedAttemptCount: Int,
        wasForced: Bool,
        attemptedAccessRecovery: Bool,
        resolution: Resolution,
        context: ServerReadFailureContext
    ) {
        let nsError = lastFailure.error as NSError
        self.failureClass = lastFailure.failureClass
        self.errorDomain = nsError.domain
        self.errorCode = nsError.code
        self.wasForced = wasForced
        self.failedAttemptCount = failedAttemptCount
        self.attemptedAccessRecovery = attemptedAccessRecovery
        self.resolution = resolution
        self.context = context
    }

    /// Whether a later attempt got the server's answer, so the climber saw nothing.
    var retryRecovered: Bool {
        resolution == .recovered
    }

    /// An unreachable server is expected to clear on its own. A refusal or anything unclassified
    /// is a defect somebody has to read about, recovered or not.
    var severity: TelemetryErrorSeverity {
        switch failureClass {
        case .unreachable: .warning
        case .refused, .unexpected: .error
        }
    }

    /// Exact values for the diagnostics that carry them privately beside the error itself.
    var diagnosticInfo: [String: String] {
        [
            "failure_class": failureClass.rawValue,
            "error_domain": errorDomain,
            "error_code": String(errorCode),
            "forced": String(wasForced),
            "failed_attempts": String(failedAttemptCount),
            "retry_recovered": String(retryRecovered),
            "access_reconcile_attempted": String(attemptedAccessRecovery),
            "resolution": resolution.rawValue,
            "seconds_since_launch": String(context.secondsSinceLaunch),
            "seconds_since_foreground": String(context.secondsSinceForeground),
            "network": context.networkInterface.rawValue
        ]
    }

    /// Analytics takes a band rather than the exact seconds, to keep the parameter countable.
    static func ageBand(seconds: Int) -> String {
        switch seconds {
        case ..<10: "under_10s"
        case ..<60: "10s_to_1m"
        case ..<600: "1m_to_10m"
        default: "over_10m"
        }
    }
}
