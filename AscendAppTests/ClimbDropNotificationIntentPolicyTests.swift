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

    @Test("A standing denial answers nothing, so the stored intent stands", .bug(id: 397))
    func aStandingDenialPreservesTheStoredIntent() {
        let decision = ClimbDropNotificationIntentPolicy.decision(
            initialStatus: .denied,
            resolvedStatus: .denied
        )

        #expect(decision == .preserve)
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
