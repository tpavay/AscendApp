import Foundation
import Observation
import UserNotifications

/// What the primer's two buttons do: ask iOS through the one shared notification state, remember
/// the answer, and set up the reminders the climber just agreed to.
///
/// The prompt always goes through ``ClimbDropNotificationState``, never a second request path, so
/// every surface that offers notifications reads one answer. Nothing here is sent anywhere: the
/// choice waits in the pre-sign-in answers like everything else the flow collects.
@MainActor
@Observable
final class NotificationPrimerViewModel {
    private(set) var isRequesting = false

    /// What the screen says, decided once when the screen opens from the climber's answers so far.
    let content: NotificationPrimerContent

    @ObservationIgnored private let coordinator: OnboardingV3Coordinator
    @ObservationIgnored private let requestAuthorization: @MainActor () async -> UNAuthorizationStatus
    @ObservationIgnored private let declineNotifications: @MainActor () async -> Void
    @ObservationIgnored private let scheduleWeeklyReminder: @MainActor (_ targetDays: Int?, _ usualMinutes: Int?) async -> Void
    @ObservationIgnored private let track: @MainActor (_ choice: PreAuthOnboardingNotificationChoice) -> Void

    init(
        coordinator: OnboardingV3Coordinator,
        loadCatalog: () -> UnlockCatalog = { HostedUnlockCatalogRepository().loadInitialCatalog() },
        now: Date = .now,
        requestAuthorization: @escaping @MainActor () async -> UNAuthorizationStatus = {
            await ClimbDropNotificationState.shared.requestDuringOnboarding()
        },
        declineNotifications: @escaping @MainActor () async -> Void = {
            await ClimbDropNotificationState.shared.disable()
        },
        scheduleWeeklyReminder: @escaping @MainActor (_ targetDays: Int?, _ usualMinutes: Int?) async -> Void = { targetDays, usualMinutes in
            // A climber who just set up has no climbs yet this week, so the plan starts from none.
            await LocalReminderScheduler.shared.reconcileWeeklyTarget(
                targetDays: targetDays,
                climbDates: [],
                usualClimbMinutes: usualMinutes
            )
        },
        track: (@MainActor (_ choice: PreAuthOnboardingNotificationChoice) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        content = NotificationPrimerContent.make(
            weeklyTargetDays: coordinator.answers.weeklyTargetDays,
            usualClimbMinutes: coordinator.answers.usualClimbMinutes,
            catalog: loadCatalog(),
            now: now
        )
        self.requestAuthorization = requestAuthorization
        self.declineNotifications = declineNotifications
        self.scheduleWeeklyReminder = scheduleWeeklyReminder
        // Telemetry reports under the flow's own analytics context unless a test replaces it.
        self.track = track ?? { [weak coordinator] choice in
            NotificationPrimerViewModel.report(choice, in: coordinator?.analyticsContext)
        }
    }

    /// TURN ON: asks iOS, records what it said, schedules the reminders if it agreed, and moves on.
    func turnOn() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        let status = await requestAuthorization()
        let choice: PreAuthOnboardingNotificationChoice = status.allowsRemoteUserVisibleNotifications ? .allowed : .denied

        record(choice)
        if choice == .allowed {
            let answers = coordinator.answers
            await scheduleWeeklyReminder(answers.weeklyTargetDays, answers.usualClimbMinutes)
        }
        coordinator.advance()
    }

    /// Not now: declines without asking iOS, so a later ask from Settings still gets the system
    /// prompt, and moves on.
    func notNow() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        await declineNotifications()
        record(.skipped)
        coordinator.advance()
    }

    private func record(_ choice: PreAuthOnboardingNotificationChoice) {
        coordinator.update { $0.notificationChoice = choice }
        track(choice)
    }

    private static func report(_ choice: PreAuthOnboardingNotificationChoice, in context: OnboardingAnalyticsContext?) {
        let status = switch choice {
        case .allowed: "allow"
        case .denied: "decline"
        case .skipped: "skip"
        }

        if let context {
            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.notificationPermissionSelected(context: context, status: status)
            )
        }
        TelemetryManager.shared.setUserProperty("notifications_inputted", value: "true")
        OnboardingAnalyticsUserProperties.setNotificationChoice(status)
    }
}
