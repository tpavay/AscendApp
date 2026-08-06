import Testing
import UserNotifications
@testable import AscendApp

/// The two enable requests that look identical from the outside: one where iOS asked the climber
/// and they said no, and one where a standing denial answered for them.
struct ClimbDropNotificationIntentPolicyTests {
    @Test("Declining the first-time iOS alert is stored as the climber's no", .bug(id: 397))
    func decliningTheSystemAlertRecordsNo() {
        let decision = ClimbDropNotificationIntentPolicy.decision(
            initialStatus: .notDetermined,
            resolvedStatus: .denied
        )

        #expect(decision == .record(false))
    }

    @Test("Allowing the first-time iOS alert is stored as a yes", .bug(id: 397))
    func allowingTheSystemAlertRecordsYes() {
        let decision = ClimbDropNotificationIntentPolicy.decision(
            initialStatus: .notDetermined,
            resolvedStatus: .authorized
        )

        #expect(decision == .record(true))
    }

    @Test("Asking again while a denial stands is a fresh yes", .bug(id: 397))
    func askingAgainUnderAStandingDenialRecordsYes() {
        let decision = ClimbDropNotificationIntentPolicy.decision(
            initialStatus: .denied,
            resolvedStatus: .denied
        )

        #expect(decision == .record(true))
    }

    @Test("Only a standing denial sends the climber to iOS Settings", .bug(id: 397))
    func onlyAStandingDenialRoutesToSystemSettings() {
        #expect(
            ClimbDropNotificationIntentPolicy.routesToSystemSettings(
                initialStatus: .denied,
                resolvedStatus: .denied
            )
        )

        // The climber answered the alert a moment ago; they are not marched anywhere over it.
        #expect(
            ClimbDropNotificationIntentPolicy.routesToSystemSettings(
                initialStatus: .notDetermined,
                resolvedStatus: .denied
            ) == false
        )

        #expect(
            ClimbDropNotificationIntentPolicy.routesToSystemSettings(
                initialStatus: .authorized,
                resolvedStatus: .authorized
            ) == false
        )
    }

    @Test("An alert that never appeared leaves the stored intent alone")
    func anUnansweredRequestPreservesTheStoredIntent() {
        let decision = ClimbDropNotificationIntentPolicy.decision(
            initialStatus: .notDetermined,
            resolvedStatus: .notDetermined
        )

        #expect(decision == .preserve)
    }

    @Test(
        "Asking while permission already stands records the ask",
        arguments: [UNAuthorizationStatus.authorized, .provisional, .ephemeral]
    )
    func askingWithPermissionAlreadyGrantedRecordsYes(status: UNAuthorizationStatus) {
        let decision = ClimbDropNotificationIntentPolicy.decision(
            initialStatus: status,
            resolvedStatus: status
        )

        #expect(decision == .record(true))
    }
}
