import Foundation
import Testing
@testable import AscendApp

@MainActor
struct OnboardingEmailOptInViewModelTests {
    @Test
    func theBoxShipsTicked() {
        // The captain's call, made after the consent objection was put to him
        // twice, and lawful because Ascend excludes all 27 EU territories.
        let viewModel = OnboardingEmailOptInViewModel(
            service: RecordingEmailPreferencesService()
        )

        #expect(OnboardingEmailOptInViewModel.shipsTicked)
        #expect(viewModel.isSelected)
    }

    @Test
    func theClimberCanUntickIt() {
        let viewModel = OnboardingEmailOptInViewModel(
            service: RecordingEmailPreferencesService()
        )

        viewModel.toggle()

        #expect(viewModel.isSelected == false)
    }

    @Test
    func continuingRecordsTheTickAsAnOnboardingDecision() async {
        let service = RecordingEmailPreferencesService()
        let viewModel = OnboardingEmailOptInViewModel(service: service)

        await viewModel.recordDecision()

        #expect(
            await service.savedDecisions == [
                StubEmailConsentDecision(isGranted: true, source: .onboarding)
            ]
        )
    }

    @Test
    func anUntickedBoxRecordsAnExplicitNo() async {
        // Leaving with the box off is an answer too. Recording it is what
        // stops the next build reading the absence as a yes again.
        let service = RecordingEmailPreferencesService()
        let viewModel = OnboardingEmailOptInViewModel(service: service)
        viewModel.toggle()

        await viewModel.recordDecision()

        #expect(
            await service.savedDecisions == [
                StubEmailConsentDecision(isGranted: false, source: .onboarding)
            ]
        )
    }

    @Test
    func aFailedWriteLeavesNoConsentBehind() async {
        // Onboarding is not held open for the network. If the write never
        // lands the preference stays unset, and unset sends nothing - the
        // right direction to fail in.
        let service = RecordingEmailPreferencesService()
        await service.setSaveError(StubError.offline)
        let viewModel = OnboardingEmailOptInViewModel(service: service)

        await viewModel.recordDecision()

        #expect(await service.savedDecisions.isEmpty)
        #expect(await service.storedConsent == .undecided)
    }
}

private enum StubError: Error {
    case offline
}

private actor RecordingEmailPreferencesService: EmailPreferencesProviding {
    private(set) var storedConsent: LifecycleEmailConsent = .undecided
    private(set) var savedDecisions: [StubEmailConsentDecision] = []
    private var saveError: Error?

    func setSaveError(_ error: Error?) {
        saveError = error
    }

    func loadConsent() async throws -> LifecycleEmailConsent {
        storedConsent
    }

    func recordConsent(
        isGranted: Bool,
        source: LifecycleEmailConsentSource
    ) async throws {
        if let saveError {
            throw saveError
        }

        savedDecisions.append(
            StubEmailConsentDecision(isGranted: isGranted, source: source)
        )
        storedConsent = LifecycleEmailConsent(isGranted: isGranted)
    }
}
