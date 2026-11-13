import Foundation

/// A `https://ascendstepper.com/go` link opened the app (`docs/universal-links.md`).
///
/// `src` is the bounded ``GoLink/Source``. `session_type` borrows the vocabulary of
/// `app_session_started` - `cold_launch` when this process was started by the link, `foreground`
/// when the app was already running or suspended - so the two join on the same words. Nothing
/// else rides along: the climber's route and sign-in state are already on the session event.
enum GoLinkAnalyticsEvent: TelemetryEvent {
    case opened(source: GoLink.Source, sessionType: AppLifecycleAnalyticsEvent.SessionType)

    var record: TelemetryRecord {
        switch self {
        case .opened(let source, let sessionType):
            TelemetryRecord(
                name: "go_link_opened",
                parameters: [
                    "src": .string(source.rawValue),
                    "session_type": .string(sessionType.rawValue)
                ]
            )
        }
    }
}
