import Foundation
import Testing
@testable import AscendApp

@MainActor
struct HeartRateVisibilityViewModelTests {
    @MainActor
    final class StubService: HeartRateVisibilityProviding {
        var stored: Bool
        var loadError: Error?
        var saveError: Error?
        var commitsBeforeFailing = false
        private(set) var recorded: [Bool] = []

        init(stored: Bool) {
            self.stored = stored
        }

        func loadIsPublic() async throws -> Bool {
            if let loadError { throw loadError }
            return stored
        }

        func setIsPublic(_ isPublic: Bool) async throws {
            if commitsBeforeFailing { stored = isPublic }
            if let saveError { throw saveError }
            recorded.append(isPublic)
            stored = isPublic
        }
    }

    struct Failure: Error {}

    @Test
    func theSwitchIsDisabledUntilTheStoredChoiceIsRead() async {
        let service = StubService(stored: false)
        let viewModel = HeartRateVisibilityViewModel(service: service)

        #expect(viewModel.isToggleDisabled)
        await viewModel.setIsPublic(false)
        #expect(service.recorded.isEmpty)

        await viewModel.load()
        #expect(viewModel.loadState == .ready)
        #expect(!viewModel.isPublic)
        #expect(!viewModel.isToggleDisabled)
    }

    @Test
    func switchingOffRecordsTheChoice() async {
        let service = StubService(stored: true)
        let viewModel = HeartRateVisibilityViewModel(service: service)
        await viewModel.load()

        await viewModel.setIsPublic(false)

        #expect(service.recorded == [false])
        #expect(!viewModel.isPublic)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func aFailedSaveMovesTheSwitchBack() async {
        let service = StubService(stored: true)
        service.saveError = Failure()
        let viewModel = HeartRateVisibilityViewModel(service: service)
        await viewModel.load()

        await viewModel.setIsPublic(false)

        #expect(viewModel.isPublic)
        #expect(viewModel.errorMessage == "Couldn't save. Check your connection.")
    }

    @Test
    func aFailureAfterTheWriteLandedShowsWhatTheServerRecorded() async {
        let service = StubService(stored: true)
        service.saveError = Failure()
        service.commitsBeforeFailing = true
        let viewModel = HeartRateVisibilityViewModel(service: service)
        await viewModel.load()

        await viewModel.setIsPublic(false)

        #expect(!viewModel.isPublic)
        #expect(viewModel.errorMessage == "Couldn't save. Check your connection.")
    }

    @Test
    func aFailedSaveThatCannotReloadKeepsThePreviousChoice() async {
        let service = StubService(stored: true)
        let viewModel = HeartRateVisibilityViewModel(service: service)
        await viewModel.load()
        service.saveError = Failure()
        service.loadError = Failure()

        await viewModel.setIsPublic(false)

        #expect(viewModel.isPublic)
        #expect(viewModel.loadState == .ready)
    }

    @Test
    func aPausedPublicationSaysSo() async {
        let service = StubService(stored: true)
        service.saveError = ProfilePublicationError.publishingPaused
        let viewModel = HeartRateVisibilityViewModel(service: service)
        await viewModel.load()

        await viewModel.setIsPublic(false)

        #expect(viewModel.isPublic)
        #expect(viewModel.errorMessage == ProfilePublicationError.publishingPaused.errorDescription)
    }

    @Test
    func aFailedReadOffersARetry() async {
        let service = StubService(stored: true)
        service.loadError = Failure()
        let viewModel = HeartRateVisibilityViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.loadState == .failed)
        #expect(viewModel.isToggleDisabled)
    }
}
