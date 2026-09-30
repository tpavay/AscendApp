import Foundation

/// A started connection: where to send the climber, and the URL scheme
/// Strava's redirect comes back on.
struct StravaAuthorizationRequest: Equatable, Sendable {
    let authorizeURL: URL
    let callbackScheme: String
}
