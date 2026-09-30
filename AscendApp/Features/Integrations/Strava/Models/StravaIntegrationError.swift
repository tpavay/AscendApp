import Foundation

/// Why the server refused a Strava request, read from the callable error's
/// `details.reason`.
enum StravaIntegrationError: Error, Equatable {
    /// The switch is off or this climber is not on the allowlist.
    case unavailable
    case alreadyConnected
    /// The authorization expired, was reused, or Strava refused the code.
    case authorizationExpired
    /// The climber unticked "Upload your activities" on Strava's consent screen.
    case missingUploadPermission
    case stravaUnreachable
    case malformedResponse
    case other(String)
}
