import Foundation
import Testing
@testable import AscendApp

@MainActor
struct EmailPreferencesViewModelTests {
    @Test
    func anUnsetPreferenceIsNotTreatedAsConsent() async {
        // The defect this screen exists to close. A climber who has never been
        // asked has not said yes, so the switch must not show one, and the
        // screen must not report a consent Ascend could not evidence.
        let service = StubEmailPreferencesService(storedConsent: .undecided)
        let viewModel = EmailPreferencesViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.consent == .undecided)
        #expect(viewModel.isLifecycleEmailsEnabled == false)
        #expect(viewModel.loadState == .ready)
    }

    @Test
    func theSwitchIsOffBeforeTheServerAnswers() async {
        // Not merely cosmetic: an on switch during the read would tell a
        // climber they had opted in before anyone had read what they chose.
        let service = StubEmailPreferencesService(storedConsent: .granted)
        let viewModel = EmailPreferencesViewModel(service: service)

        #expect(viewModel.isLifecycleEmailsEnabled == false)

        await viewModel.load()

        #expect(viewModel.isLifecycleEmailsEnabled == true)
    }

    @Test
    func turningItOnFromUnsetRecordsARealDecision() async {
        let service = StubEmailPreferencesService(storedConsent: .undecided)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await viewModel.setLifecycleEmailsEnabled(true)

        #expect(await service.savedDecisions == [.init(isGranted: true, source: .settings)])
        #expect(viewModel.consent == .granted)
    }

    @Test
    func loadReadsTheServerPreference() async {
        let service = StubEmailPreferencesService(storedConsent: .declined)
        let viewModel = EmailPreferencesViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.isLifecycleEmailsEnabled == false)
        #expect(viewModel.loadState == .ready)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func loadSurfacesAnUnsubscribeMadeFromAnEmailLink() async {
        // The unsubscribe link flips the same server preference, so the toggle
        // has to reflect it rather than trust a stale local value.
        let service = StubEmailPreferencesService(storedConsent: .granted)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()
        #expect(viewModel.isLifecycleEmailsEnabled == true)

        await service.setStoredConsent(.declined)
        await viewModel.load()

        #expect(viewModel.consent == .declined)
        #expect(viewModel.isLifecycleEmailsEnabled == false)
    }

    @Test
    func failedLoadReportsTheFailure() async {
        let service = StubEmailPreferencesService(storedConsent: .granted)
        await service.setLoadError(StubError.offline)
        let viewModel = EmailPreferencesViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.loadState == .failed)
        #expect(viewModel.errorMessage != nil)
    }

    @Test
    func aFailedRefreshKeepsTheLastKnownGoodValue() async {
        // Returning to an open screen with no network must not take a working
        // toggle away: the value already read is still the best one we have.
        let service = StubEmailPreferencesService(storedConsent: .declined)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await service.setLoadError(StubError.offline)
        await viewModel.load()

        #expect(viewModel.consent == .declined)
        #expect(viewModel.loadState == .ready)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isToggleDisabled == false)
    }

    @Test
    func aSucceedingRefreshPicksUpAServerSideChange() async {
        let service = StubEmailPreferencesService(storedConsent: .granted)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()
        #expect(viewModel.isLifecycleEmailsEnabled == true)

        await service.setStoredConsent(.declined)
        await viewModel.load()

        #expect(viewModel.isLifecycleEmailsEnabled == false)
        #expect(viewModel.loadState == .ready)
    }

    @Test
    func concurrentLoadsReadTheServerOnce() async {
        let service = StubEmailPreferencesService(storedConsent: .declined)
        let viewModel = EmailPreferencesViewModel(service: service)

        async let first: Void = viewModel.load()
        async let second: Void = viewModel.load()
        _ = await (first, second)

        #expect(await service.loadCount == 1)
        #expect(viewModel.loadState == .ready)
        #expect(viewModel.isLifecycleEmailsEnabled == false)
    }

    @Test
    func aWriteThatLandsDuringARefreshSurvivesIt() async {
        // The refresh read the value before the user turned the toggle off, so
        // resolving it afterwards must not put the toggle back on while the
        // server holds off.
        let service = SuspendingEmailPreferencesService(storedConsent: .granted)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()
        #expect(viewModel.isLifecycleEmailsEnabled == true)

        await service.startSuspendingLoads()
        async let refresh: Void = viewModel.load()
        await service.waitForSuspendedLoad()

        await viewModel.setLifecycleEmailsEnabled(false)
        #expect(viewModel.isLifecycleEmailsEnabled == false)

        await service.resumeSuspendedLoad(returning: .granted)
        await refresh

        #expect(viewModel.isLifecycleEmailsEnabled == false)
        #expect(viewModel.loadState == .ready)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func aFailedWriteThatRevertsDuringARefreshKeepsItsMessage() async {
        // The revert settles the value too, so a read that started earlier must
        // not overwrite it or clear the failure the user needs to see.
        let service = SuspendingEmailPreferencesService(storedConsent: .granted)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await service.startSuspendingLoads()
        await service.setSaveError(StubError.offline)
        async let refresh: Void = viewModel.load()
        await service.waitForSuspendedLoad()

        await viewModel.setLifecycleEmailsEnabled(false)

        await service.resumeSuspendedLoad(returning: .declined)
        await refresh

        #expect(viewModel.isLifecycleEmailsEnabled == true)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.loadState == .ready)
    }

    @Test
    func togglingOffWritesThePreference() async {
        let service = StubEmailPreferencesService(storedConsent: .granted)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await viewModel.setLifecycleEmailsEnabled(false)

        #expect(await service.savedDecisions == [.init(isGranted: false, source: .settings)])
        #expect(viewModel.consent == .declined)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isUpdating == false)
    }

    @Test
    func togglingBackOnWritesThePreference() async {
        let service = StubEmailPreferencesService(storedConsent: .declined)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await viewModel.setLifecycleEmailsEnabled(true)

        #expect(await service.savedDecisions == [.init(isGranted: true, source: .settings)])
        #expect(viewModel.consent == .granted)
    }

    @Test
    func aFailedWriteRevertsTheToggle() async {
        // The save-failed state on the board. A preference that silently fails
        // to save is the same class of bug as a workout that silently fails to
        // back up: the switch goes back and says so.
        let service = StubEmailPreferencesService(storedConsent: .granted)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()
        await service.setSaveError(StubError.offline)

        await viewModel.setLifecycleEmailsEnabled(false)

        #expect(viewModel.isLifecycleEmailsEnabled == true)
        #expect(viewModel.errorMessage == "Couldn't save. Check your connection.")
        #expect(viewModel.isUpdating == false)
    }

    @Test
    func aFailedWriteFromUnsetLeavesTheChoiceUnmade() async {
        // The revert must land back on undecided rather than inventing a no:
        // a failed write recorded nothing, so nothing was decided.
        let service = StubEmailPreferencesService(storedConsent: .undecided)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()
        await service.setSaveError(StubError.offline)

        await viewModel.setLifecycleEmailsEnabled(true)

        #expect(viewModel.consent == .undecided)
        #expect(viewModel.isLifecycleEmailsEnabled == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test
    func writingTheCurrentValueIsANoOp() async {
        let service = StubEmailPreferencesService(storedConsent: .granted)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await viewModel.setLifecycleEmailsEnabled(true)

        #expect(await service.savedDecisions.isEmpty)
    }

    @Test
    func turningAnUnsetPreferenceOffStillRecordsTheNo() async {
        // Undecided and declined both send nothing, but only one is an answer.
        // Reaching for the switch is an answer even when the switch does not
        // appear to move.
        let service = StubEmailPreferencesService(storedConsent: .undecided)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await viewModel.setLifecycleEmailsEnabled(false)

        #expect(await service.savedDecisions == [.init(isGranted: false, source: .settings)])
        #expect(viewModel.consent == .declined)
    }

    @Test
    func theToggleStaysDisabledUntilTheServerValueArrives() async {
        let service = StubEmailPreferencesService(storedConsent: .granted)
        let viewModel = EmailPreferencesViewModel(service: service)

        #expect(viewModel.isToggleDisabled == true)

        await viewModel.load()

        #expect(viewModel.isToggleDisabled == false)
    }

    @Test
    func aRetryAfterAFailedLoadBringsTheSwitchBack() async {
        // The screen exists so a climber can record an answer. A read that
        // failed once must not leave the switch dead until they navigate away
        // and back: the status line retries in place.
        let service = StubEmailPreferencesService(storedConsent: .granted)
        await service.setLoadError(StubError.offline)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()
        #expect(viewModel.loadState == .failed)
        #expect(viewModel.isToggleDisabled == true)

        await service.setLoadError(nil)
        await viewModel.load()

        #expect(viewModel.loadState == .ready)
        #expect(viewModel.isToggleDisabled == false)
        #expect(viewModel.isLifecycleEmailsEnabled == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func aRetryThatFailsAgainStillSaysSo() async {
        let service = StubEmailPreferencesService(storedConsent: .granted)
        await service.setLoadError(StubError.offline)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await viewModel.load()

        #expect(viewModel.loadState == .failed)
        #expect(viewModel.errorMessage == "Couldn't load your email settings.")
        #expect(await service.loadCount == 2)
    }

    @Test
    func theToggleStaysDisabledWhenTheServerValueIsUnknown() async {
        let service = StubEmailPreferencesService(storedConsent: .granted)
        await service.setLoadError(StubError.offline)
        let viewModel = EmailPreferencesViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.isToggleDisabled == true)
    }
}

private enum StubError: Error {
    case offline
}

/// One recorded decision, so a test can assert what was written and where the
/// climber said it, not just that something was written.
struct StubEmailConsentDecision: Equatable, Sendable {
    let isGranted: Bool
    let source: LifecycleEmailConsentSource
}

/// Parks a read on a continuation so a test can land a write in the middle of
/// it without depending on timing.
private actor SuspendingEmailPreferencesService: EmailPreferencesProviding {
    private var storedConsent: LifecycleEmailConsent
    private var saveError: Error?
    private var isSuspendingLoads = false
    private var suspendedLoad: CheckedContinuation<LifecycleEmailConsent, Error>?
    private var loadObserver: CheckedContinuation<Void, Never>?

    init(storedConsent: LifecycleEmailConsent) {
        self.storedConsent = storedConsent
    }

    func setSaveError(_ error: Error?) {
        saveError = error
    }

    func startSuspendingLoads() {
        isSuspendingLoads = true
    }

    func waitForSuspendedLoad() async {
        guard suspendedLoad == nil else { return }

        await withCheckedContinuation { continuation in
            loadObserver = continuation
        }
    }

    func resumeSuspendedLoad(returning value: LifecycleEmailConsent) {
        let continuation = suspendedLoad
        suspendedLoad = nil
        continuation?.resume(returning: value)
    }

    func loadConsent() async throws -> LifecycleEmailConsent {
        guard isSuspendingLoads else { return storedConsent }

        return try await withCheckedThrowingContinuation { continuation in
            suspendedLoad = continuation
            let observer = loadObserver
            loadObserver = nil
            observer?.resume()
        }
    }

    func recordConsent(
        isGranted: Bool,
        source: LifecycleEmailConsentSource
    ) async throws {
        if let saveError {
            throw saveError
        }

        storedConsent = LifecycleEmailConsent(isGranted: isGranted)
    }
}

private actor StubEmailPreferencesService: EmailPreferencesProviding {
    private var storedConsent: LifecycleEmailConsent
    private var loadError: Error?
    private var saveError: Error?
    private(set) var savedDecisions: [StubEmailConsentDecision] = []
    private(set) var loadCount = 0

    init(storedConsent: LifecycleEmailConsent) {
        self.storedConsent = storedConsent
    }

    func setStoredConsent(_ value: LifecycleEmailConsent) {
        storedConsent = value
    }

    func setLoadError(_ error: Error?) {
        loadError = error
    }

    func setSaveError(_ error: Error?) {
        saveError = error
    }

    func loadConsent() async throws -> LifecycleEmailConsent {
        loadCount += 1

        if let loadError {
            throw loadError
        }

        return storedConsent
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
