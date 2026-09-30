import Foundation

/// Every call the app makes about Strava. The client secret, the tokens and
/// the uploads all live in Cloud Functions; the app only starts and ends a
/// connection.
@MainActor
protocol StravaIntegrationClient: AnyObject {
    func fetchStatus() async throws -> StravaConnectionStatus
    func beginConnect() async throws -> StravaAuthorizationRequest
    func completeConnect(code: String, state: String) async throws -> StravaConnectionStatus
    func disconnect() async throws -> StravaConnectionStatus
}
