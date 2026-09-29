import Foundation

/// Shows Strava's consent page and returns the URL Strava redirected to.
@MainActor
protocol StravaAuthorizationPresenting: AnyObject {
    /// Returns nil when the climber closed the sheet without finishing.
    func authorize(_ request: StravaAuthorizationRequest) async throws -> URL?
}
