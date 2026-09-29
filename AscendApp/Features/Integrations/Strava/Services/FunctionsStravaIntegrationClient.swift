import Foundation
@preconcurrency import FirebaseFunctions

@MainActor
final class FunctionsStravaIntegrationClient: StravaIntegrationClient {
    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "us-central1")) {
        self.functions = functions
    }

    func fetchStatus() async throws -> StravaConnectionStatus {
        StravaConnectionStatus(callablePayload: try await call("stravaGetStatus"))
    }

    func beginConnect() async throws -> StravaAuthorizationRequest {
        let payload = try await call("stravaBeginConnect") as? [String: Any]
        guard let urlString = payload?["authorizeUrl"] as? String,
              let url = URL(string: urlString),
              url.scheme == "https",
              let scheme = payload?["callbackScheme"] as? String,
              !scheme.isEmpty else {
            throw StravaIntegrationError.malformedResponse
        }
        return StravaAuthorizationRequest(authorizeURL: url, callbackScheme: scheme)
    }

    func completeConnect(code: String, state: String) async throws -> StravaConnectionStatus {
        StravaConnectionStatus(
            callablePayload: try await call("stravaCompleteConnect", data: ["code": code, "state": state])
        )
    }

    func disconnect() async throws -> StravaConnectionStatus {
        StravaConnectionStatus(callablePayload: try await call("stravaDisconnect"))
    }

    private func call(_ name: String, data: [String: String]? = nil) async throws -> Any? {
        do {
            let callable = functions.httpsCallable(name)
            let result = if let data {
                try await callable.call(data)
            } else {
                try await callable.call()
            }
            return result.data
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            throw Self.integrationError(for: error)
        }
    }

    nonisolated static func integrationError(for error: NSError) -> StravaIntegrationError {
        let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        switch details?["reason"] as? String {
        case "unavailable": return .unavailable
        case "already_connected": return .alreadyConnected
        case "expired": return .authorizationExpired
        case "missing_scope": return .missingUploadPermission
        case "strava_unreachable": return .stravaUnreachable
        default: return .other(error.localizedDescription)
        }
    }
}
