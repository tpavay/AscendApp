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

    /// The bounded set of routes a session reports. Mirrors ``AppRootRoute`` one for one, plus
    /// `unresolved` for a cold launch whose routing inputs had still not settled when the bounded
    /// wait expired - a real, countable outcome, never a fallback for an unmapped route.
    enum RootRoute: String, CaseIterable, Sendable {
        case updateRequired = "update_required"
        case preAuthOnboarding = "pre_auth_onboarding"
        case restoringSession = "restoring_session"
        case resolving
        case paywall
        case mainApp = "main_app"
        case unresolved

        /// `restoring_session` and `resolving` are waypoints the app leaves on its
        /// own, so a launch that is sitting on one has not chosen a destination yet.
        var isResolved: Bool {
            switch self {
            case .updateRequired, .preAuthOnboarding, .paywall, .mainApp:
                true
            case .restoringSession, .resolving, .unresolved:
                false
            }
        }

        init(_ route: AppRootRoute) {
            switch route {
            case .updateRequired:
                self = .updateRequired
            case .preAuthOnboarding:
                self = .preAuthOnboarding
            case .restoringSession:
                self = .restoringSession
            case .resolving:
                self = .resolving
            case .paywall:
                self = .paywall
            case .mainApp:
                self = .mainApp
            }
        }
    }

    /// The bounded set of authentication answers a session reports, plus `unresolved` for a cold
    /// launch whose Firebase session restore had not finished when the bounded wait expired.
    enum AuthState: String, CaseIterable, Sendable {
        case authenticated
        case authenticating
        case restoringSession = "restoring_session"
        case unauthenticated
        case unresolved

        /// Signed in or signed out are answers. Restoring and authenticating are the question.
        var isResolved: Bool {
            switch self {
            case .authenticated, .unauthenticated:
                true
            case .authenticating, .restoringSession, .unresolved:
                false
            }
        }

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
