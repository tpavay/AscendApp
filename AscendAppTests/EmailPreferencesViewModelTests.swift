import Foundation
import Testing
@testable import AscendApp

@MainActor
struct EmailPreferencesViewModelTests {
    @Test
    func loadReadsTheServerPreference() async {
        let service = StubEmailPreferencesService(storedValue: false)
        let viewModel = EmailPreferencesViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.isLifecycleEmailsEnabled == false)
        #expect(viewModel.loadState == .ready)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func loadSurfacesAnUnsubscribeMadeFromAnEmailLink() async {
        // The unsubscribe link flips the same server preference, so the toggle
        // has to reflect it rather than trust a stale local default.
        let service = StubEmailPreferencesService(storedValue: false)
        let viewModel = EmailPreferencesViewModel(service: service)
        #expect(viewModel.isLifecycleEmailsEnabled == true)

        await viewModel.load()

        #expect(viewModel.isLifecycleEmailsEnabled == false)
    }

    @Test
    func failedLoadReportsTheFailure() async {
        let service = StubEmailPreferencesService(storedValue: true)
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
        let service = StubEmailPreferencesService(storedValue: false)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await service.setLoadError(StubError.offline)
        await viewModel.load()

        #expect(viewModel.isLifecycleEmailsEnabled == false)
        #expect(viewModel.loadState == .ready)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isToggleDisabled == false)
    }

    @Test
    func aSucceedingRefreshPicksUpAServerSideChange() async {
        let service = StubEmailPreferencesService(storedValue: true)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()
        #expect(viewModel.isLifecycleEmailsEnabled == true)

        await service.setStoredValue(false)
        await viewModel.load()

        #expect(viewModel.isLifecycleEmailsEnabled == false)
        #expect(viewModel.loadState == .ready)
    }

    @Test
    func concurrentLoadsReadTheServerOnce() async {
        let service = StubEmailPreferencesService(storedValue: false)
        let viewModel = EmailPreferencesViewModel(service: service)

        async let first: Void = viewModel.load()
        async let second: Void = viewModel.load()
        _ = await (first, second)

        #expect(await service.loadCount == 1)
        #expect(viewModel.loadState == .ready)
        #expect(viewModel.isLifecycleEmailsEnabled == false)
    }

    @Test
    func togglingOffWritesThePreference() async {
        let service = StubEmailPreferencesService(storedValue: true)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await viewModel.setLifecycleEmailsEnabled(false)

        #expect(await service.savedValues == [false])
        #expect(viewModel.isLifecycleEmailsEnabled == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isUpdating == false)
    }

    @Test
    func togglingBackOnWritesThePreference() async {
        let service = StubEmailPreferencesService(storedValue: false)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await viewModel.setLifecycleEmailsEnabled(true)

        #expect(await service.savedValues == [true])
        #expect(viewModel.isLifecycleEmailsEnabled == true)
    }

    @Test
    func aFailedWriteRevertsTheToggle() async {
        let service = StubEmailPreferencesService(storedValue: true)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()
        await service.setSaveError(StubError.offline)

        await viewModel.setLifecycleEmailsEnabled(false)

        #expect(viewModel.isLifecycleEmailsEnabled == true)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.isUpdating == false)
    }

    @Test
    func writingTheCurrentValueIsANoOp() async {
        let service = StubEmailPreferencesService(storedValue: true)
        let viewModel = EmailPreferencesViewModel(service: service)
        await viewModel.load()

        await viewModel.setLifecycleEmailsEnabled(true)

        #expect(await service.savedValues.isEmpty)
    }

    @Test
    func theToggleStaysDisabledUntilTheServerValueArrives() async {
        let service = StubEmailPreferencesService(storedValue: true)
        let viewModel = EmailPreferencesViewModel(service: service)

        #expect(viewModel.isToggleDisabled == true)

        await viewModel.load()

        #expect(viewModel.isToggleDisabled == false)
    }

    @Test
    func theToggleStaysDisabledWhenTheServerValueIsUnknown() async {
        let service = StubEmailPreferencesService(storedValue: true)
        await service.setLoadError(StubError.offline)
        let viewModel = EmailPreferencesViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.isToggleDisabled == true)
    }
}

private enum StubError: Error {
    case offline
}

private actor StubEmailPreferencesService: EmailPreferencesProviding {
    private var storedValue: Bool
    private var loadError: Error?
    private var saveError: Error?
    private(set) var savedValues: [Bool] = []
    private(set) var loadCount = 0

    init(storedValue: Bool) {
        self.storedValue = storedValue
    }

    func setStoredValue(_ value: Bool) {
        storedValue = value
    }

    func setLoadError(_ error: Error?) {
        loadError = error
    }

    func setSaveError(_ error: Error?) {
        saveError = error
    }

    func loadLifecycleEmailsEnabled() async throws -> Bool {
        loadCount += 1

        if let loadError {
            throw loadError
        }

        return storedValue
    }

    func setLifecycleEmailsEnabled(_ isEnabled: Bool) async throws {
        if let saveError {
            throw saveError
        }

        savedValues.append(isEnabled)
        storedValue = isEnabled
    }
}
