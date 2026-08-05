import Testing
@testable import AscendApp

@MainActor
struct ScopedProfileUpdateTests {
    // The Settings root renders `errorMessage` inline. A failure a pushed
    // editor left on it followed the climber back out and sat under an
    // unrelated screen, so every profile editor takes its failure by return
    // value and the shared channel is empty either way.
    @Test
    func aFailedUpdateReturnsItsMessageAndLeavesTheSharedChannelEmpty() async {
        let viewModel = makeViewModel()

        let failure = await viewModel.scopedProfileUpdate(fallback: "Fallback") {
            viewModel.errorMessage = "Failed to update birthday"
            return false
        }

        #expect(failure == "Failed to update birthday")
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func aSucceedingUpdateReturnsNoMessage() async {
        let viewModel = makeViewModel()

        let failure = await viewModel.scopedProfileUpdate(fallback: "Fallback") { true }

        #expect(failure == nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func aSilentFailureStillReportsTheCallerSFallback() async {
        let viewModel = makeViewModel()

        let failure = await viewModel.scopedProfileUpdate(fallback: "Fallback") { false }

        #expect(failure == "Fallback")
        #expect(viewModel.errorMessage == nil)
    }

    // A message left over from an earlier failure would otherwise be handed
    // back as though the update that just ran had produced it.
    @Test
    func anEarlierFailureIsNotMisattributedToTheNextUpdate() async {
        let viewModel = makeViewModel()
        viewModel.errorMessage = "Failed to update gender"

        let failure = await viewModel.scopedProfileUpdate(fallback: "Fallback") { true }

        #expect(failure == nil)
        #expect(viewModel.errorMessage == nil)
    }

    private func makeViewModel() -> AuthenticationViewModel {
        AuthenticationViewModel(observesFirebaseAuth: false)
    }
}
