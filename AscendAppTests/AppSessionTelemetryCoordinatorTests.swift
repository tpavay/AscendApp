import Foundation
import Testing
@testable import AscendApp

@MainActor
struct AppSessionTelemetryCoordinatorTests {
    @Test("Cold launch waits for routing to settle, then reports the real route exactly once")
    func coldLaunchReportsResolvedDimensionsExactlyOnce() throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink)

        coordinator.observeColdLaunch(
            rootRoute: .restoringSession,
            authenticationState: .restoringSession
        )
        coordinator.observeColdLaunch(
            rootRoute: .resolving,
            authenticationState: .authenticated
        )
        #expect(sink.records.isEmpty)

        coordinator.observeColdLaunch(
            rootRoute: .mainApp,
            authenticationState: .authenticated
        )
        // A remount replays the root task over an already-reported launch.
        coordinator.observeColdLaunch(
            rootRoute: .paywall,
            authenticationState: .authenticated
        )

        #expect(sink.records.count == 1)
        let record = try #require(sink.records.first)
        #expect(record.name == "app_session_started")
        #expect(record.parameters["session_id"] == .string(Self.coldLaunchID.uuidString))
        #expect(record.parameters["session_type"] == .string("cold_launch"))
        #expect(record.parameters["root_route"] == .string("main_app"))
        #expect(record.parameters["auth_state"] == .string("authenticated"))
        #expect(Set(record.parameters.keys) == Self.sessionParameterKeys)
    }

    @Test("A launch that never settles still reports, marking both dimensions unresolved")
    func coldLaunchTimeoutReportsUnresolvedDimensions() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink, coldLaunchResolutionWait: {})

        coordinator.observeColdLaunch(
            rootRoute: .resolving,
            authenticationState: .restoringSession
        )

        try await waitForColdLaunchResolutionTimeout(coordinator)

        #expect(sink.records.count == 1)
        let record = try #require(sink.records.first)
        #expect(record.parameters["session_type"] == .string("cold_launch"))
        #expect(record.parameters["root_route"] == .string("unresolved"))
        #expect(record.parameters["auth_state"] == .string("unresolved"))
        #expect(Set(record.parameters.keys) == Self.sessionParameterKeys)
    }

    @Test("The timeout only marks the dimension that is genuinely still unknown")
    func coldLaunchTimeoutKeepsTheDimensionThatSettled() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink, coldLaunchResolutionWait: {})

        // The lockout resolves above authentication, so the route can settle while the Firebase
        // session restore is still in flight.
        coordinator.observeColdLaunch(
            rootRoute: .updateRequired,
            authenticationState: .restoringSession
        )

        try await waitForColdLaunchResolutionTimeout(coordinator)

        let record = try #require(sink.records.first)
        #expect(record.parameters["root_route"] == .string("update_required"))
        #expect(record.parameters["auth_state"] == .string("unresolved"))
    }

    @Test("A launch that settles before the timeout is never reported twice")
    func coldLaunchTimeoutCannotReportASecondSession() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink, coldLaunchResolutionWait: {})

        coordinator.observeColdLaunch(
            rootRoute: .resolving,
            authenticationState: .restoringSession
        )
        let pendingWait = try #require(coordinator.coldLaunchResolutionTask)

        coordinator.observeColdLaunch(
            rootRoute: .mainApp,
            authenticationState: .authenticated
        )
        await pendingWait.value

        #expect(sink.records.count == 1)
        let record = try #require(sink.records.first)
        #expect(record.parameters["root_route"] == .string("main_app"))
        #expect(record.parameters["auth_state"] == .string("authenticated"))
    }

    @Test("Backgrounding an unsettled launch flushes it, marking only what is still unknown")
    func backgroundBeforeResolutionFlushesTheColdLaunch() throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink, coldLaunchResolutionWait: {})

        coordinator.observeColdLaunch(
            rootRoute: .updateRequired,
            authenticationState: .restoringSession
        )
        coordinator.recordDidEnterBackground(at: Date(timeIntervalSince1970: 10_000))

        #expect(sink.records.count == 1)
        let record = try #require(sink.records.first)
        #expect(record.parameters["session_id"] == .string(Self.coldLaunchID.uuidString))
        #expect(record.parameters["session_type"] == .string("cold_launch"))
        #expect(record.parameters["root_route"] == .string("update_required"))
        #expect(record.parameters["auth_state"] == .string("unresolved"))
        #expect(Set(record.parameters.keys) == Self.sessionParameterKeys)
    }

    @Test("The bounded wait cannot report again after a background flushed the launch")
    func resumeAfterABackgroundFlushDoesNotReportAgain() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink, coldLaunchResolutionWait: {})
        let initialDate = Date(timeIntervalSince1970: 10_000)

        coordinator.observeColdLaunch(
            rootRoute: .resolving,
            authenticationState: .restoringSession
        )
        let pendingWait = try #require(coordinator.coldLaunchResolutionTask)

        coordinator.recordDidEnterBackground(at: initialDate)
        await pendingWait.value

        coordinator.observeColdLaunch(
            rootRoute: .mainApp,
            authenticationState: .authenticated
        )
        coordinator.recordWillEnterForeground(
            at: initialDate.addingTimeInterval(
                AppSessionTelemetryCoordinator.inactivityThreshold
            ),
            rootRoute: .mainApp,
            authenticationState: .authenticated
        )

        #expect(sink.records.count == 2)
        let coldLaunch = try #require(sink.records.first)
        #expect(coldLaunch.parameters["session_type"] == .string("cold_launch"))
        #expect(coldLaunch.parameters["root_route"] == .string("unresolved"))
        #expect(coldLaunch.parameters["auth_state"] == .string("unresolved"))

        let foreground = try #require(sink.records.last)
        #expect(foreground.parameters["session_type"] == .string("foreground"))
        #expect(foreground.parameters["root_route"] == .string("main_app"))
        #expect(foreground.parameters["auth_state"] == .string("authenticated"))
    }

    @Test("Backgrounding a launch that already reported does not report a second one")
    func backgroundAfterResolutionDoesNotDoubleReport() throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink, coldLaunchResolutionWait: {})

        coordinator.observeColdLaunch(
            rootRoute: .mainApp,
            authenticationState: .authenticated
        )
        coordinator.recordDidEnterBackground(at: Date(timeIntervalSince1970: 10_000))

        #expect(sink.records.count == 1)
        let record = try #require(sink.records.first)
        #expect(record.parameters["session_type"] == .string("cold_launch"))
        #expect(record.parameters["root_route"] == .string("main_app"))
        #expect(record.parameters["auth_state"] == .string("authenticated"))
    }

    @Test("A background before the root view ever observed a launch reports nothing")
    func backgroundWithoutAnObservedLaunchReportsNothing() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink, coldLaunchResolutionWait: {})

        coordinator.recordDidEnterBackground(at: Date(timeIntervalSince1970: 10_000))

        #expect(sink.records.isEmpty)
    }

    @Test("Brief app switches do not start sessions, while the inactivity boundary does")
    func foregroundSessionHonorsBothSidesOfInactivityThreshold() throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink)
        let initialDate = Date(timeIntervalSince1970: 10_000)

        coordinator.observeColdLaunch(
            rootRoute: .mainApp,
            authenticationState: .authenticated
        )
        coordinator.recordDidEnterBackground(at: initialDate)
        coordinator.recordWillEnterForeground(
            at: initialDate.addingTimeInterval(AppSessionTelemetryCoordinator.inactivityThreshold - 1),
            rootRoute: .mainApp,
            authenticationState: .authenticated
        )

        coordinator.recordDidEnterBackground(at: initialDate.addingTimeInterval(2_000))
        coordinator.recordWillEnterForeground(
            at: initialDate.addingTimeInterval(
                2_000 + AppSessionTelemetryCoordinator.inactivityThreshold
            ),
            rootRoute: .updateRequired,
            authenticationState: .restoringSession
        )

        #expect(sink.records.count == 2)
        let foreground = try #require(sink.records.last)
        #expect(foreground.name == "app_session_started")
        #expect(foreground.parameters["session_id"] == .string(Self.foregroundID.uuidString))
        #expect(foreground.parameters["session_type"] == .string("foreground"))
        #expect(foreground.parameters["root_route"] == .string("update_required"))
        #expect(foreground.parameters["auth_state"] == .string("restoring_session"))
        #expect(Set(foreground.parameters.keys) == Self.sessionParameterKeys)
    }

    @Test("Foreground notifications without a background transition emit nothing")
    func foregroundWithoutBackgroundEmitsNothing() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink)

        coordinator.recordWillEnterForeground(
            at: Date(timeIntervalSince1970: 10_000),
            rootRoute: .resolving,
            authenticationState: .restoringSession
        )

        #expect(sink.records.isEmpty)
    }

    @Test("Session dimensions remain bounded to the app lifecycle contract")
    func sessionDimensionsAreBoundedEnums() {
        #expect(
            Set(AppLifecycleAnalyticsEvent.SessionType.allCases.map(\.rawValue)) == [
                "cold_launch",
                "foreground"
            ]
        )
        #expect(
            Set(AppLifecycleAnalyticsEvent.RootRoute.allCases.map(\.rawValue)) == [
                "update_required",
                "signed_out",
                "signing_in",
                "restoring_session",
                "resolving",
                "onboarding",
                "paywall",
                "main_app",
                "unresolved"
            ]
        )
        #expect(
            Set(AppLifecycleAnalyticsEvent.AuthState.allCases.map(\.rawValue)) == [
                "authenticated",
                "authenticating",
                "restoring_session",
                "unauthenticated",
                "unresolved"
            ]
        )
    }

    /// The bounded wait is the only thing that can report the session from here, so awaiting the
    /// task it armed is what proves the timeout emitted rather than a race deciding it.
    private func waitForColdLaunchResolutionTimeout(
        _ coordinator: AppSessionTelemetryCoordinator
    ) async throws {
        let pendingWait = try #require(coordinator.coldLaunchResolutionTask)
        await pendingWait.value
    }

    private func makeCoordinator(
        sink: InMemoryTelemetrySink,
        coldLaunchResolutionWait: (@Sendable () async -> Void)? = nil
    ) -> AppSessionTelemetryCoordinator {
        var sessionIDs = [Self.coldLaunchID, Self.foregroundID]
        let makeSessionID: () -> UUID = { sessionIDs.removeFirst() }

        guard let coldLaunchResolutionWait else {
            return AppSessionTelemetryCoordinator(
                telemetry: makeTestTelemetry(sink: sink),
                sessionID: makeSessionID
            )
        }

        return AppSessionTelemetryCoordinator(
            telemetry: makeTestTelemetry(sink: sink),
            sessionID: makeSessionID,
            coldLaunchResolutionWait: coldLaunchResolutionWait
        )
    }

    private static let coldLaunchID = UUID(
        uuid: (0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11)
    )
    private static let foregroundID = UUID(
        uuid: (0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22)
    )
    private static let sessionParameterKeys: Set<String> = [
        "app_environment",
        "build_config",
        "app_version",
        "build_number",
        "session_id",
        "session_type",
        "root_route",
        "auth_state"
    ]
}
