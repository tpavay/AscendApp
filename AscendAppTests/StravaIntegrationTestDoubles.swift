import Foundation
@testable import AscendApp

@MainActor
final class FakeStravaIntegrationClient: StravaIntegrationClient {
    static let request = StravaAuthorizationRequest(
        authorizeURL: URL(string: "https://www.strava.com/oauth/mobile/authorize?client_id=1")!,
        callbackScheme: "ascendapp"
    )

    var status: StravaConnectionStatus
    var completedStatus: StravaConnectionStatus?
    var disconnectedStatus: StravaConnectionStatus?
    var fetchError: Error?
    var beginError: Error?
    var completeError: Error?
    var disconnectError: Error?
    private(set) var completions: [(code: String, state: String)] = []
    private(set) var disconnects = 0

    init(status: StravaConnectionStatus) {
        self.status = status
    }

    func fetchStatus() async throws -> StravaConnectionStatus {
        if let fetchError { throw fetchError }
        return status
    }

    func beginConnect() async throws -> StravaAuthorizationRequest {
        if let beginError { throw beginError }
        return Self.request
    }

    func completeConnect(code: String, state: String) async throws -> StravaConnectionStatus {
        completions.append((code, state))
        if let completeError { throw completeError }
        return completedStatus ?? status
    }

    func disconnect() async throws -> StravaConnectionStatus {
        disconnects += 1
        if let disconnectError { throw disconnectError }
        return disconnectedStatus ?? status
    }
}

@MainActor
final class FakeStravaAuthorizationPresenter: StravaAuthorizationPresenting {
    let callback: URL?
    private(set) var presented: [StravaAuthorizationRequest] = []

    init(callback: URL? = nil) {
        self.callback = callback
    }

    func authorize(_ request: StravaAuthorizationRequest) async throws -> URL? {
        presented.append(request)
        return callback
    }
}
