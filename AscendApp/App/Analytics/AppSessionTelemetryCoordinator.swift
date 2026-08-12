import Foundation

@MainActor
final class AppSessionTelemetryCoordinator {
    static let shared = AppSessionTelemetryCoordinator()

    /// A foreground starts a new analytics session after 30 minutes away.
    /// Short app switches stay within the current session.
    static let inactivityThreshold: TimeInterval = 30 * 60

    /// How long a cold launch waits for routing and authentication to settle before reporting the
    /// session with whatever has settled by then. Five seconds covers a routine Firebase session
    /// restore, onboarding read and entitlement refresh, while keeping a stalled network from
    /// delaying - or suppressing - the retention boundary the whole activation funnel hangs off.
    static let coldLaunchResolutionTimeout: TimeInterval = 5

    private let telemetry: TelemetryManager
    private let sessionID: () -> UUID
    private let coldLaunchResolutionWait: @Sendable () async -> Void
    private var didRecordColdLaunch = false
    private var latestColdLaunchRoute: AppLifecycleAnalyticsEvent.RootRoute = .unresolved
    private var latestColdLaunchAuthState: AppLifecycleAnalyticsEvent.AuthState = .unresolved
    private var backgroundedAt: Date?

    /// The pending bounded wait, retained so a launch that settles first can cancel it.
    private(set) var coldLaunchResolutionTask: Task<Void, Never>?

    init(
        telemetry: TelemetryManager = .shared,
        sessionID: @escaping () -> UUID = UUID.init,
        coldLaunchResolutionWait: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(
                for: .seconds(AppSessionTelemetryCoordinator.coldLaunchResolutionTimeout)
            )
        }
    ) {
        self.telemetry = telemetry
        self.sessionID = sessionID
        self.coldLaunchResolutionWait = coldLaunchResolutionWait
    }

    /// Reports the cold-launch session once routing and authentication have both settled, or once
    /// the bounded wait expires - whichever lands first.
    ///
    /// Call it on every routing or authentication change from launch onwards. Sampling the first
    /// tick alone can only ever see a pre-resolution snapshot, because the routing inputs resolve
    /// after the root task starts. Only one session is ever reported, so a remount replaying the
    /// root task cannot start a second one.
    func observeColdLaunch(
        rootRoute: AppRootRoute,
        authenticationState: AuthenticationState
    ) {
        guard didRecordColdLaunch == false else { return }

        latestColdLaunchRoute = .init(rootRoute)
        latestColdLaunchAuthState = .init(authenticationState)

        guard latestColdLaunchRoute.isResolved, latestColdLaunchAuthState.isResolved else {
            startColdLaunchResolutionWaitIfNeeded()
            return
        }

        recordColdLaunch(
            rootRoute: latestColdLaunchRoute,
            authState: latestColdLaunchAuthState
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
            rootRoute: .init(rootRoute),
            authState: .init(authenticationState)
        )
    }

    private func startColdLaunchResolutionWaitIfNeeded() {
        guard coldLaunchResolutionTask == nil else { return }

        let wait = coldLaunchResolutionWait
        coldLaunchResolutionTask = Task { @MainActor [weak self] in
            await wait()
            guard Task.isCancelled == false else { return }

            self?.recordColdLaunchWithWhateverSettled()
        }
    }

    private func recordColdLaunchWithWhateverSettled() {
        guard didRecordColdLaunch == false else { return }

        recordColdLaunch(
            rootRoute: latestColdLaunchRoute.isResolved ? latestColdLaunchRoute : .unresolved,
            authState: latestColdLaunchAuthState.isResolved ? latestColdLaunchAuthState : .unresolved
        )
    }

    private func recordColdLaunch(
        rootRoute: AppLifecycleAnalyticsEvent.RootRoute,
        authState: AppLifecycleAnalyticsEvent.AuthState
    ) {
        didRecordColdLaunch = true
        coldLaunchResolutionTask?.cancel()
        coldLaunchResolutionTask = nil

        recordSession(type: .coldLaunch, rootRoute: rootRoute, authState: authState)
    }

    private func recordSession(
        type: AppLifecycleAnalyticsEvent.SessionType,
        rootRoute: AppLifecycleAnalyticsEvent.RootRoute,
        authState: AppLifecycleAnalyticsEvent.AuthState
    ) {
        telemetry.track(
            AppLifecycleAnalyticsEvent.sessionStarted(
                sessionID: sessionID(),
                sessionType: type,
                rootRoute: rootRoute,
                authState: authState
            )
        )
    }
}
