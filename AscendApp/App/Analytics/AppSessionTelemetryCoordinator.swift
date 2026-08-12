import Foundation

@MainActor
final class AppSessionTelemetryCoordinator {
    static let shared = AppSessionTelemetryCoordinator()

    /// A foreground starts a new analytics session after 30 minutes away.
    /// Short app switches stay within the current session.
    static let inactivityThreshold: TimeInterval = 30 * 60

    private let telemetry: TelemetryManager
    private let sessionID: () -> UUID
    private var didRecordColdLaunch = false
    private var backgroundedAt: Date?

    init(
        telemetry: TelemetryManager = .shared,
        sessionID: @escaping () -> UUID = UUID.init
    ) {
        self.telemetry = telemetry
        self.sessionID = sessionID
    }

    func recordColdLaunch(
        rootRoute: AppRootRoute,
        authenticationState: AuthenticationState
    ) {
        guard didRecordColdLaunch == false else { return }
        didRecordColdLaunch = true

        recordSession(
            type: .coldLaunch,
            rootRoute: rootRoute,
            authenticationState: authenticationState
        )
    }

    func recordDidEnterBackground(at date: Date = .now) {
        if backgroundedAt == nil {
            backgroundedAt = date
        }
    }

    func recordWillEnterForeground(
        at date: Date = .now,
        rootRoute: AppRootRoute,
        authenticationState: AuthenticationState
    ) {
        guard let backgroundedAt else { return }
        self.backgroundedAt = nil

        guard date.timeIntervalSince(backgroundedAt) >= Self.inactivityThreshold else { return }

        recordSession(
            type: .foreground,
            rootRoute: rootRoute,
            authenticationState: authenticationState
        )
    }

    private func recordSession(
        type: AppLifecycleAnalyticsEvent.SessionType,
        rootRoute: AppRootRoute,
        authenticationState: AuthenticationState
    ) {
        telemetry.track(
            AppLifecycleAnalyticsEvent.sessionStarted(
                sessionID: sessionID(),
                sessionType: type,
                rootRoute: .init(rootRoute),
                authState: .init(authenticationState)
            )
        )
    }
}
