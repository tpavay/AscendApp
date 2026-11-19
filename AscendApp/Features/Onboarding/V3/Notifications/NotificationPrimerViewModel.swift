import Foundation
import Observation
import UserNotifications

/// What the primer's one button does: ask iOS through the one shared notification state, remember
/// the answer, and move on whatever it was (Guideline 5.1.1(iv) forbids a way past the request).
/// Writing that answer is what sets up the reminders: ``LocalReminderCoordinator`` follows it.
///
/// The prompt always goes through ``ClimbDropNotificationState``, never a second request path, so
/// every surface that offers notifications reads one answer. Nothing here is sent anywhere: the
/// choices, the email box included, wait in the pre-sign-in answers like everything else the flow
/// collects.
@MainActor
@Observable
final class NotificationPrimerViewModel {
    private(set) var isRequesting = false

    /// The email box. It ships ticked like the legacy screen's did
    /// (``OnboardingEmailOptInViewModel/shipsTicked``), and a climber who comes back to this step
    /// finds it as they left it.
    private(set) var emailOptIn: Bool

    /// What the screen says, decided once when the screen opens from the climber's answers so far.
    let content: NotificationPrimerContent

    @ObservationIgnored private let coordinator: OnboardingV3Coordinator
    @ObservationIgnored private let requestAuthorization: @MainActor () async -> UNAuthorizationStatus
    @ObservationIgnored private let track: @MainActor (_ choice: PreAuthOnboardingNotificationChoice) -> Void

    init(
        coordinator: OnboardingV3Coordinator,
        loadCatalog: () -> UnlockCatalog = { HostedUnlockCatalogRepository().loadInitialCatalog() },
        now: Date = .now,
        requestAuthorization: @escaping @MainActor () async -> UNAuthorizationStatus = {
            await ClimbDropNotificationState.shared.requestDuringOnboarding()
        },
        telemetry: TelemetryManager = .shared,
        track: (@MainActor (_ choice: PreAuthOnboardingNotificationChoice) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        emailOptIn = coordinator.answers.emailOptIn ?? OnboardingEmailOptInViewModel.shipsTicked
        content = NotificationPrimerContent.make(
            weeklyTargetDays: coordinator.answers.weeklyTargetDays,
            usualClimbMinutes: coordinator.answers.usualClimbMinutes,
            catalog: loadCatalog(),
            now: now
        )
        self.requestAuthorization = requestAuthorization
        // Telemetry reports under the flow's own analytics context unless a test replaces it.
        self.track = track ?? { [weak coordinator] choice in
            NotificationPrimerViewModel.report(
                choice,
                emailOptIn: coordinator?.answers.emailOptIn,
                in: coordinator?.analyticsContext,
                telemetry: telemetry
            )
        }
    }

    func toggleEmailOptIn() {
        emailOptIn.toggle()
    }

    /// TURN ON: asks iOS, records what it said, and moves on.
    func turnOn() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        let status = await requestAuthorization()
        let choice: PreAuthOnboardingNotificationChoice = status.allowsRemoteUserVisibleNotifications ? .allowed : .denied

        record(choice)
        coordinator.advance()
    }

    /// Email is a separate answer from push: it is saved whichever way iOS was answered, so a
    /// refusal never discards a ticked box, and unticking never stops the prompt.
    private func record(_ choice: PreAuthOnboardingNotificationChoice) {
        let emailOptIn = emailOptIn
        coordinator.update {
            $0.notificationChoice = choice
            $0.emailOptIn = emailOptIn
        }
        track(choice)
    }

    /// One answer event carries both choices the step collects. The email box is read from the
    /// answers `record` just wrote, so the event says what was saved, not what the box showed
    /// earlier. Counts of the box are consent intent: the delivered consent is written after sign-in.
    private static func report(
        _ choice: PreAuthOnboardingNotificationChoice,
        emailOptIn: Bool?,
        in context: OnboardingAnalyticsContext?,
        telemetry: TelemetryManager
    ) {
        let status = switch choice {
        case .allowed: "allow"
        case .denied: "decline"
        case .skipped: "skip"
        }

        if let context {
            telemetry.track(
                OnboardingAnalyticsEvent.notificationPermissionSelected(
                    context: context,
                    status: status,
                    emailOptIn: emailOptIn
                )
            )
        }
        telemetry.setUserProperty("notifications_inputted", value: "true")
        OnboardingAnalyticsUserProperties.setNotificationChoice(status, telemetry: telemetry)
        if let emailOptIn {
            OnboardingAnalyticsUserProperties.setEmailOptIn(emailOptIn, telemetry: telemetry)
        }
    }
}
