import Foundation
import os
import SwiftData
import Testing
@testable import AscendApp

/// The Totals stickers' three standings cost leaderboard reads, so a sheet reads them once: only
/// when Totals is first asked for, and never again when the climber changes the period.
@MainActor
struct StickersTotalsStandingsTests {
    private final class CountingStandingReader: ShareStandingReading {
        private let reads = OSAllocatedUnfairLock<[LeaderboardTimeFrame]>(initialState: [])

        var timeFrames: [LeaderboardTimeFrame] { reads.withLock { $0 } }

        func standing(userId: String, timeFrame: LeaderboardTimeFrame) async -> ShareTotalsSnapshot.Standing? {
            reads.withLock { $0.append(timeFrame) }
            switch timeFrame {
            case .weekly: return ShareTotalsSnapshot.Standing(position: 3, field: 40)
            case .monthly: return ShareTotalsSnapshot.Standing(position: 9, field: 120)
            default: return ShareTotalsSnapshot.Standing(position: 31, field: 2_400)
            }
        }
    }

    private func makeModel(reader: CountingStandingReader) throws -> StickersViewModel {
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let suite = "StickersTotalsStandingsTests.\(UUID().uuidString)"
        return StickersViewModel(
            subject: .fixture(),
            modelContext: ModelContext(container),
            userId: "climber",
            repository: ShareTotalsRepository(standings: reader),
            store: StickerStyleStore(defaults: UserDefaults(suiteName: suite)!)
        )
    }

    @Test
    func standingsAreReadOnceAndReusedForEveryPeriod() async throws {
        let reader = CountingStandingReader()
        let model = try makeModel(reader: reader)
        #expect(reader.timeFrames.isEmpty, "opening the sheet read the leaderboards")

        model.scope = .totals
        await model.loadTotals()
        #expect(model.totals?.standing == ShareTotalsSnapshot.Standing(position: 3, field: 40))

        model.period = .month
        await model.loadTotals()
        #expect(model.totals?.period == .month)
        #expect(model.totals?.standing == ShareTotalsSnapshot.Standing(position: 9, field: 120))

        model.period = .year
        await model.loadTotals()
        #expect(model.totals?.standing == ShareTotalsSnapshot.Standing(position: 31, field: 2_400))

        #expect(reader.timeFrames.count == 3, "a period change read the leaderboards again: \(reader.timeFrames)")
        #expect(Set(reader.timeFrames) == [.weekly, .monthly, .yearly])
    }
}
