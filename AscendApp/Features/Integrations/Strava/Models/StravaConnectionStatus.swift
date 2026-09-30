import Foundation

/// What the server says about this climber and Strava.
///
/// `isAvailable` is whether they may start a connection: the integration is
/// switched on server-side and they are on its allowlist, because the Strava
/// app can only hold a fixed number of connected athletes until Strava approves
/// more. A connected climber is always shown their connection, so they can
/// disconnect even after the switch is turned off.
struct StravaConnectionStatus: Equatable, Sendable {
    let isAvailable: Bool
    let isConnected: Bool
    let athleteName: String?

    static let hidden = StravaConnectionStatus(isAvailable: false, isConnected: false, athleteName: nil)

    /// Whether the Integrations screen shows Strava at all.
    var isVisible: Bool {
        isAvailable || isConnected
    }

    init(isAvailable: Bool, isConnected: Bool, athleteName: String?) {
        self.isAvailable = isAvailable
        self.isConnected = isConnected
        self.athleteName = athleteName
    }

    /// Reads the `stravaGetStatus` callable's payload, failing closed: anything
    /// unreadable hides the integration rather than offering a connect the
    /// server has not allowed.
    init(callablePayload payload: Any?) {
        let values = payload as? [String: Any]
        let name = (values?["athleteName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            isAvailable: values?["available"] as? Bool ?? false,
            isConnected: values?["connected"] as? Bool ?? false,
            athleteName: name?.isEmpty == false ? name : nil
        )
    }
}
