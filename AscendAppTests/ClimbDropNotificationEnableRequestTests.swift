import Testing
import UserNotifications
@testable import AscendApp

/// The wiring `PushNotificationService.requestClimbDropNotifications` runs: which answer reaches
/// the device, whether the climber is handed to iOS Settings, and in what order.
@MainActor
struct ClimbDropNotificationEnableRequestTests {
    @Test("Declining the first-time alert records the no and opens nothing", .bug(id: 397))
    func decliningTheFirstAlertRecordsNo() async {
        let recorder = EnableRequestRecorder()
        let request = makeRequest(
            initialStatus: .notDetermined,
            alertOutcome: .denied,
            recorder: recorder
        )

        let status = await request.run(opensSettingsWhenDenied: true)

        #expect(status == .denied)
        #expect(recorder.effects == [
            .presentedAlert,
            .recordedIntent(false),
            .synchronized(.denied)
        ])
    }

    @Test("Allowing the first-time alert records the yes", .bug(id: 397))
    func allowingTheFirstAlertRecordsYes() async {
        let recorder = EnableRequestRecorder()
        let request = makeRequest(
            initialStatus: .notDetermined,
            alertOutcome: .authorized,
            recorder: recorder
        )

        let status = await request.run(opensSettingsWhenDenied: true)

        #expect(status == .authorized)
        #expect(recorder.effects == [
            .presentedAlert,
            .recordedIntent(true),
            .synchronized(.authorized)
        ])
    }

    @Test("A standing denial records the yes and opens iOS Settings before syncing", .bug(id: 397))
    func aStandingDenialRecordsTheYesThenRoutesOutAheadOfTheSync() async {
        let recorder = EnableRequestRecorder()
        let request = makeRequest(initialStatus: .denied, recorder: recorder)

        let status = await request.run(opensSettingsWhenDenied: true)

        #expect(status == .denied)
        // The answer is on the device before the route opens, and the server is last in line:
        // nothing the network does can stand between the tap and the screen it asked for.
        #expect(recorder.effects == [
            .recordedIntent(true),
            .openedSystemSettings,
            .synchronized(.denied)
        ])
    }

    @Test("Onboarding records the yes without leaving the flow", .bug(id: 397))
    func onboardingNeverRoutesOutOfTheFlow() async {
        let recorder = EnableRequestRecorder()
        let request = makeRequest(initialStatus: .denied, recorder: recorder)

        let status = await request.run(opensSettingsWhenDenied: false)

        #expect(status == .denied)
        #expect(recorder.effects == [
            .recordedIntent(true),
            .synchronized(.denied)
        ])
    }

    @Test("Asking while permission already stands never raises an alert")
    func anAlreadyAllowedPermissionSkipsTheAlert() async {
        let recorder = EnableRequestRecorder()
        let request = makeRequest(initialStatus: .authorized, recorder: recorder)

        let status = await request.run(opensSettingsWhenDenied: true)

        #expect(status == .authorized)
        #expect(recorder.effects == [
            .recordedIntent(true),
            .synchronized(.authorized)
        ])
    }

    private func makeRequest(
        initialStatus: UNAuthorizationStatus,
        alertOutcome: UNAuthorizationStatus = .authorized,
        recorder: EnableRequestRecorder
    ) -> ClimbDropNotificationEnableRequest {
        ClimbDropNotificationEnableRequest(
            currentAuthorizationStatus: { initialStatus },
            presentSystemAuthorizationAlert: {
                recorder.effects.append(.presentedAlert)
                return alertOutcome
            },
            recordIntent: { recorder.effects.append(.recordedIntent($0)) },
            openSystemNotificationSettings: { recorder.effects.append(.openedSystemSettings) },
            synchronizeInBackground: { recorder.effects.append(.synchronized($0)) }
        )
    }
}

@MainActor
private final class EnableRequestRecorder {
    enum Effect: Equatable {
        case presentedAlert
        case recordedIntent(Bool)
        case openedSystemSettings
        case synchronized(UNAuthorizationStatus)
    }

    var effects: [Effect] = []
}
