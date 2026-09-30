import Foundation

/// What Strava's redirect back to the app carried.
enum StravaAuthorizationCallback: Equatable {
    /// The climber approved; the server exchanges the code.
    case approved(code: String, state: String)
    /// The climber tapped Cancel on Strava's consent screen.
    case denied
    /// Anything else Strava sent back.
    case invalid

    /// Parses `ascendapp://<callback domain>/...?state=...&code=...&scope=...`,
    /// or `...?error=access_denied`.
    init(url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        if value("error") == "access_denied" {
            self = .denied
        } else if let code = value("code"), let state = value("state") {
            self = .approved(code: code, state: state)
        } else {
            self = .invalid
        }
    }
}
