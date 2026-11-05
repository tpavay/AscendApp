import Foundation
import Observation

/// What the sign-in screen needs that is not drawing: which of its two modes it is in, the board
/// it shows, and the sign-in itself.
@MainActor
@Observable
final class OnboardingAuthViewModel {
    enum Mode: Equatable {
        /// The last step of the flow: the weekly board, the climber's empty row, two buttons.
        case claimSpot
        /// "Already climbing? Sign in" from the first screen: no board, then normal routing.
        case returning
    }

    let mode: Mode
    private(set) var board: PublicWeeklyBoard?
    private(set) var hasLoadedBoard = false

    @ObservationIgnored private let repository: PublicWeeklyBoardRepository
    @ObservationIgnored private let now: () -> Date

    init(
        mode: Mode,
        repository: PublicWeeklyBoardRepository = .live,
        now: @escaping () -> Date = { Date() }
    ) {
        self.mode = mode
        self.repository = repository
        self.now = now
    }

    /// The two ways in. A climber who reached the sign-in screen from the first screen is a
    /// returning one, and so is one who asked to be: the paywall's "Already climbing? Sign in" goes
    /// through the same step as a purchase does, so the step it came from cannot tell them apart.
    static func mode(
        arrivedFrom previous: OnboardingV3Step?,
        returningRequest: OnboardingAuthReturningRequest = OnboardingAuthReturningRequest()
    ) -> Mode {
        previous == .welcome || returningRequest.isSet ? .returning : .claimSpot
    }

    /// Whether the board is part of this mode at all.
    var showsBoard: Bool { mode == .claimSpot }

    var entries: [ModeratedLeaderboardEntry] {
        board?.moderatedEntries() ?? []
    }

    func loadBoard() async {
        guard showsBoard, !hasLoadedBoard else { return }

        board = await repository.fetch(now())
        hasLoadedBoard = true
    }
}
