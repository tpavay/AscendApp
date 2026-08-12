import Foundation

enum AppLifecycleAnalyticsEvent: TelemetryEvent {
    case firstOpened(appVersion: String, buildNumber: String)
    case sessionStarted(
        sessionID: UUID,
        sessionType: SessionType,
        rootRoute: RootRoute,
        authState: AuthState
    )

    var record: TelemetryRecord {
        switch self {
        case .firstOpened(let appVersion, let buildNumber):
            TelemetryRecord(
                name: "app_first_opened",
                parameters: [
                    "first_open_app_version": .string(appVersion),
                    "first_open_build_number": .string(buildNumber)
                ]
            )

        case .sessionStarted(let sessionID, let sessionType, let rootRoute, let authState):
            TelemetryRecord(
                name: "app_session_started",
                parameters: [
                    "session_id": .string(sessionID.uuidString),
                    "session_type": .string(sessionType.rawValue),
                    "root_route": .string(rootRoute.rawValue),
                    "auth_state": .string(authState.rawValue)
                ]
            )
        }
    }
}

extension AppLifecycleAnalyticsEvent {
    enum SessionType: String, CaseIterable, Sendable {
        case coldLaunch = "cold_launch"
        case foreground
    }

    enum RootRoute: String, CaseIterable, Sendable {
        case updateRequired = "update_required"
        case signedOut = "signed_out"
        case signingIn = "signing_in"
        case restoringSession = "restoring_session"
        case resolving
        case onboarding
        case paywall
        case mainApp = "main_app"

        init(_ route: AppRootRoute) {
            switch route {
            case .updateRequired:
                self = .updateRequired
            case .signedOut:
                self = .signedOut
            case .signingIn:
                self = .signingIn
            case .restoringSession:
                self = .restoringSession
            case .resolving:
                self = .resolving
            case .onboarding:
                self = .onboarding
            case .paywall:
                self = .paywall
            case .mainApp:
                self = .mainApp
            }
        }
    }

    enum AuthState: String, CaseIterable, Sendable {
        case authenticated
        case authenticating
        case restoringSession = "restoring_session"
        case unauthenticated

        init(_ state: AuthenticationState) {
            switch state {
            case .authenticated:
                self = .authenticated
            case .authenticatingWithApple,
                 .authenticatingWithGoogle,
                 .authenticatingWithInternalQA:
                self = .authenticating
            case .restoringSession:
                self = .restoringSession
            case .unauthenticated:
                self = .unauthenticated
            }
        }
    }
}
