import Foundation

/// A `https://ascendstepper.com/go` link opened the app (`docs/universal-links.md`).
///
/// `src` is the bounded ``GoLink/Source``, and nothing else rides along: the climber's route and
/// sign-in state are already on `app_session_started`.
enum GoLinkAnalyticsEvent: TelemetryEvent {
    case opened(source: GoLink.Source)

    var record: TelemetryRecord {
        switch self {
        case .opened(let source):
            TelemetryRecord(
                name: "go_link_opened",
                parameters: ["src": .string(source.rawValue)]
            )
        }
    }
}
