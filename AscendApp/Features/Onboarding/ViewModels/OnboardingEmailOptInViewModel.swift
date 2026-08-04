import Foundation
import Observation

/// The email opt-in on the onboarding notifications step.
///
/// The box ships ticked. That is the captain's call, made after the consent
/// objection was put to him twice, and it is lawful because Ascend excludes all
/// 27 EU territories (`data/app-setup-runbook.md`, section 4d). Whichever way
/// the box ends up, the answer is written down: a tick and an untick are both
/// decisions, and the point of this screen is that Ascend stops inferring one.
@MainActor
@Observable
final class OnboardingEmailOptInViewModel {
    /// How the box arrives. Named rather than inlined so the decision has one
    /// place to change if the territory answer ever changes with it.
    static let shipsTicked = true

    private(set) var isSelected: Bool
    private let service: EmailPreferencesProviding

    init(
        service: EmailPreferencesProviding = EmailPreferencesService(),
        isSelected: Bool = OnboardingEmailOptInViewModel.shipsTicked
    ) {
        self.service = service
        self.isSelected = isSelected
    }

    func toggle() {
        isSelected.toggle()
    }

    /// Writes the decision without holding onboarding open for it.
    ///
    /// The task is unstructured on purpose: it outlives the screen the climber
    /// is already leaving. A write that never lands leaves the preference
    /// unset, and unset sends nothing - the safe direction to fail in.
    func startRecordingDecision() {
        Task {
            await recordDecision()
        }
    }

    /// The awaitable form, for tests and for any caller that wants the result.
    func recordDecision() async {
        do {
            try await service.recordConsent(
                isGranted: isSelected,
                source: .onboarding
            )
        } catch {
            TelemetryManager.shared.recordError(
                error,
                context: .network,
                code: "onboarding_email_consent_record_failed",
                additionalInfo: ["is_granted": isSelected ? "true" : "false"]
            )
        }
    }
}
