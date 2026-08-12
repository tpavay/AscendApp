import Foundation
import Testing
@testable import AscendApp

@MainActor
struct AppSessionTelemetryCoordinatorTests {
    @Test("Cold launch emits one session even when the root task appears again")
    func coldLaunchEmitsExactlyOnce() throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink)

        coordinator.recordColdLaunch(
            rootRoute: .signedOut,
            authenticationState: .unauthenticated
        )
        coordinator.recordColdLaunch(
            rootRoute: .mainApp,
            authenticationState: .authenticated
        )

        #expect(sink.records.count == 1)
        let record = try #require(sink.records.first)
        #expect(record.name == "app_session_started")
        #expect(record.parameters["session_id"] == .string(Self.coldLaunchID.uuidString))
        #expect(record.parameters["session_type"] == .string("cold_launch"))
        #expect(record.parameters["root_route"] == .string("signed_out"))
        #expect(record.parameters["auth_state"] == .string("unauthenticated"))
        #expect(Set(record.parameters.keys) == Self.sessionParameterKeys)
    }

    @Test("Brief app switches do not start sessions, while the inactivity boundary does")
    func foregroundSessionHonorsBothSidesOfInactivityThreshold() throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let coordinator = makeCoordinator(sink: sink)
        let initialDate = Date(timeIntervalSince1970: 10_000)

        coordinator.recordColdLaunch(
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
                "main_app"
            ]
        )
        #expect(
            Set(AppLifecycleAnalyticsEvent.AuthState.allCases.map(\.rawValue)) == [
                "authenticated",
                "authenticating",
                "restoring_session",
                "unauthenticated"
            ]
        )
    }

    private func makeCoordinator(sink: InMemoryTelemetrySink) -> AppSessionTelemetryCoordinator {
        var sessionIDs = [Self.coldLaunchID, Self.foregroundID]
        return AppSessionTelemetryCoordinator(
            telemetry: makeTestTelemetry(sink: sink),
            sessionID: { sessionIDs.removeFirst() }
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
