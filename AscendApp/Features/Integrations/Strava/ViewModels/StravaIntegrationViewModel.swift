import Foundation
import Observation

/// UI state for the Strava card on the Integrations screen.
///
/// The card shows nothing until the server has answered, and nothing at all
/// for a climber who may not connect: offering a connect Strava would refuse
/// is exactly what the allowlist exists to prevent.
@MainActor
@Observable
final class StravaIntegrationViewModel {
    private(set) var status: StravaConnectionStatus = .hidden
    private(set) var isWorking = false
    var errorMessage: String?

    private let client: any StravaIntegrationClient
    private let presenter: any StravaAuthorizationPresenting
    private let appURLScheme: String

    init(
        client: any StravaIntegrationClient = FunctionsStravaIntegrationClient(),
        presenter: any StravaAuthorizationPresenting = WebStravaAuthorizationPresenter(),
        appURLScheme: String = AscendURLScheme.current
    ) {
        self.client = client
        self.presenter = presenter
        self.appURLScheme = appURLScheme
    }

    var statusLabel: String? {
        guard status.isConnected else { return nil }
        guard let athleteName = status.athleteName else { return "Connected" }
        return "Connected · \(athleteName)"
    }

    var description: String {
        status.isConnected
            ? "Every climb you finish lands on your Strava as a Stair-Stepper activity, with steps, floors, time, heart rate and calories."
            : "Send every climb you finish to your Strava: steps, floors, time, heart rate and calories, including any from Apple Health. Ascend only asks to upload, reads nothing from your Strava, and deletes its access when you disconnect."
    }

    /// Reads the current status. A failed read keeps whatever was last shown,
    /// so a flaky network never makes a connected climber's card vanish.
    func refresh() async {
        do {
            status = try await client.fetchStatus()
        } catch {
            return
        }
    }

    func connect() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let request = try await client.beginConnect()
            // Strava hands the code to whichever installed build claims the redirect's scheme,
            // so a project configured for another build's scheme would connect that build.
            guard request.callbackScheme.lowercased() == appURLScheme else {
                TelemetryManager.shared.recordError(
                    StravaIntegrationError.malformedResponse,
                    context: .network,
                    code: "strava_callback_scheme_mismatch",
                    additionalInfo: ["callback_scheme": request.callbackScheme, "app_scheme": appURLScheme]
                )
                errorMessage = Self.message(for: .malformedResponse)
                return
            }
            guard let callbackURL = try await presenter.authorize(request) else { return }
            switch StravaAuthorizationCallback(url: callbackURL) {
            case let .approved(code, state):
                status = try await client.completeConnect(code: code, state: state)
            case .denied:
                return
            case .invalid:
                errorMessage = Self.message(for: .authorizationExpired)
            }
        } catch let error as StravaIntegrationError {
            if error == .alreadyConnected || error == .unavailable {
                await refresh()
            }
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = Self.message(for: .other(error.localizedDescription))
        }
    }

    func disconnect() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            status = try await client.disconnect()
        } catch {
            errorMessage = "Couldn't disconnect Strava. Try again."
        }
    }

    static func message(for error: StravaIntegrationError) -> String? {
        switch error {
        case .alreadyConnected:
            return nil
        case .unavailable:
            return "Strava isn't open to your account yet."
        case .authorizationExpired:
            return "That Strava sign-in expired. Connect again."
        case .missingUploadPermission:
            return "Ascend needs permission to upload your activities. Connect again and leave it ticked."
        case .stravaUnreachable:
            return "Strava didn't answer. Try again in a minute."
        case .malformedResponse, .other:
            return "Couldn't connect Strava. Try again."
        }
    }
}
