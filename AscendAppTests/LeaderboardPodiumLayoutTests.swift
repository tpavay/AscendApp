import Foundation
import Testing
@testable import AscendApp

struct LeaderboardPodiumLayoutTests {
    @Test
    func pedestalsAreOrderedLeftCentreRight() {
        let layout = LeaderboardPodiumLayout(entries: makeEntries(ranks: [1, 2, 3]))

        #expect(layout.slots.map(\.position) == [2, 1, 3])
    }

    @Test
    func topClimberStandsCentre() {
        let layout = LeaderboardPodiumLayout(entries: makeEntries(ranks: [1, 2, 3]))
        let centre = layout.slots.first { $0.position == 1 }

        #expect(centre?.entry?.rank == 1)
    }

    @Test
    func pedestalsFillInLeaderboardOrder() {
        let layout = LeaderboardPodiumLayout(entries: makeEntries(ranks: [1, 2, 3]))

        // Left pedestal takes the runner-up, right takes third.
        #expect(layout.slots.first { $0.position == 2 }?.entry?.rank == 2)
        #expect(layout.slots.first { $0.position == 3 }?.entry?.rank == 3)
    }

    @Test
    func tiedClimbersBothReachThePodium() {
        // Keying pedestals by rank collapsed these two onto one slot and dropped a
        // climber outright.
        let entries = makeEntries(ranks: [1, 1, 3])
        let layout = LeaderboardPodiumLayout(entries: entries)

        let seatedIDs = layout.slots.compactMap { $0.entry?.userId }
        #expect(seatedIDs.count == 3)
        #expect(Set(seatedIDs) == Set(entries.map(\.userId)))
    }

    @Test
    func tiedClimbersKeepTheirOwnRankOnWhicheverPedestalTheyStand() {
        let layout = LeaderboardPodiumLayout(entries: makeEntries(ranks: [1, 1, 3]))

        let centre = layout.slots.first { $0.position == 1 }
        let left = layout.slots.first { $0.position == 2 }
        let right = layout.slots.first { $0.position == 3 }

        // The left pedestal seats a gold-ranked climber — position is geometry, the
        // rank is the climber's own.
        #expect(centre?.displayedRank == 1)
        #expect(left?.displayedRank == 1)
        #expect(left?.isTied == true)
        #expect(right?.displayedRank == 3)
        #expect(right?.isTied == false)
    }

    @Test
    func threeWayTieForGoldSeatsEveryone() {
        let entries = makeEntries(ranks: [1, 1, 1])
        let layout = LeaderboardPodiumLayout(entries: entries)

        #expect(layout.slots.compactMap { $0.entry?.userId }.count == 3)
        #expect(layout.slots.allSatisfy { $0.displayedRank == 1 })
        #expect(layout.slots.allSatisfy { $0.isTied })
    }

    @Test
    func emptyPedestalShowsTheNextRankUpForGrabs() {
        let layout = LeaderboardPodiumLayout(entries: makeEntries(ranks: [1]))

        let left = layout.slots.first { $0.position == 2 }
        let right = layout.slots.first { $0.position == 3 }

        #expect(left?.entry == nil)
        #expect(left?.displayedRank == 2)
        #expect(right?.entry == nil)
        #expect(right?.displayedRank == 3)
    }

    @Test
    func twoClimbersTiedForGoldLeaveRankThreeOpen() {
        // Competition ranking skips 2, so the open pedestal is honestly labelled 3.
        let layout = LeaderboardPodiumLayout(entries: makeEntries(ranks: [1, 1]))

        let right = layout.slots.first { $0.position == 3 }
        #expect(right?.entry == nil)
        #expect(right?.displayedRank == 3)
    }

    @Test
    func emptyBoardRendersThreeOpenPedestals() {
        let layout = LeaderboardPodiumLayout(entries: [])

        #expect(layout.slots.count == 3)
        #expect(layout.slots.allSatisfy { $0.entry == nil })
        #expect(layout.slots.allSatisfy { $0.isTied == false })
    }

    // MARK: - Podium / list split

    @Test
    func podiumAndListTogetherCoverEveryClimberExactlyOnce() {
        // Four climbers tied for 2nd all hold a top-3 rank. A rank <= 3 / rank > 3
        // split put the fourth in neither bucket and it vanished from the screen.
        let entries = makeEntries(ranks: [1, 2, 2, 2, 2])

        let podium = LeaderboardPodiumLayout.podiumEntries(from: entries)
        let list = LeaderboardPodiumLayout.listEntries(from: entries)

        #expect(podium.count == 3)
        #expect(list.count == 2)
        #expect(podium.map(\.userId) + list.map(\.userId) == entries.map(\.userId))
    }

    @Test
    func splitHandlesBoardsSmallerThanThePodium() {
        let entries = makeEntries(ranks: [1, 2])

        #expect(LeaderboardPodiumLayout.podiumEntries(from: entries).count == 2)
        #expect(LeaderboardPodiumLayout.listEntries(from: entries).isEmpty)
    }

    @Test
    func splitHandlesAnEmptyBoard() {
        #expect(LeaderboardPodiumLayout.podiumEntries(from: []).isEmpty)
        #expect(LeaderboardPodiumLayout.listEntries(from: []).isEmpty)
    }

    private func makeEntries(ranks: [Int]) -> [LeaderboardEntry] {
        let tiedRanks = Set(ranks.filter { rank in ranks.count(where: { $0 == rank }) > 1 })

        return ranks.enumerated().map { index, rank in
            LeaderboardEntry(
                userId: "user-\(index)",
                displayName: "Climber \(index)",
                rank: rank,
                value: Double(1_000 - rank),
                formattedValue: "\(1_000 - rank)",
                isTied: tiedRanks.contains(rank)
            )
        }
    }
}
