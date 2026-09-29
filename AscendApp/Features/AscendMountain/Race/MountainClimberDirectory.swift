import Foundation
import Observation

/// The climbers someone can filter the Mountain's race down to: the few whose best is nearest
/// theirs first, then everyone on the board, most steps first, a page at a time.
///
/// Every climber here has a best on the session's board, because racing someone means racing
/// that best - so the board is the whole list, and nobody without a climb to race is offered.
/// Search narrows the pages already read; it asks for further pages while it can still find more,
/// up to `searchPageLimit`, so a long board is searched without being read end to end.
@MainActor
@Observable
final class MountainClimberDirectory {
    static let pageSize = 40
    static let closeCount = 3
    static let searchPageLimit = 10

    private(set) var closeToYourBest: [LiveReplayLeaderboardRow] = []
    private(set) var everyone: [LiveReplayLeaderboardRow] = []
    private(set) var isLoading = false
    private(set) var didFail = false

    @ObservationIgnored private let board: MountainRaceBoard
    @ObservationIgnored private let context: LiveReplayLeaderboardContext
    @ObservationIgnored private var next: MountainRaceBoardCursor?
    @ObservationIgnored private var pagesRead = 0
    @ObservationIgnored private var reachedEnd = false

    init(board: MountainRaceBoard, context: LiveReplayLeaderboardContext) {
        self.board = board
        self.context = context
    }

    var canLoadMore: Bool {
        !reachedEnd && !isLoading
    }

    /// Reads the climbers nearest `steps` and the first page of everyone.
    func load(nearSteps steps: Int) async {
        guard pagesRead == 0, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let close = board.bests(context: context, near: max(steps, 1), limit: Self.closeCount)
            async let page = board.bests(context: context, after: nil, limit: Self.pageSize)
            closeToYourBest = try await close.filter { !$0.isCurrentUser }
            accept(try await page)
            didFail = false
        } catch {
            didFail = true
        }
    }

    /// Reads the next page of everyone, if there is one.
    func loadMore() async {
        guard canLoadMore, pagesRead > 0 else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            accept(try await board.bests(context: context, after: next, limit: Self.pageSize))
            didFail = false
        } catch {
            didFail = true
        }
    }

    /// Whether a search that has found fewer than it could show should read another page.
    func shouldReadOnForSearch(matches: Int) -> Bool {
        canLoadMore && pagesRead < Self.searchPageLimit && matches < Self.pageSize
    }

    private func accept(_ page: MountainRaceBoardPage) {
        let known = Set(everyone.map(\.id))
        everyone += page.rows.filter { !$0.isCurrentUser && !known.contains($0.id) }
        next = page.next
        reachedEnd = page.next == nil
        pagesRead += 1
    }
}
