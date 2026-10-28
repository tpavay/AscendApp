import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// The Stickers tab's seasonal row exists only inside a theme's window, and only on This climb.
@MainActor
struct StickersSeasonalRowTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func makeModel(now: Date) throws -> StickersViewModel {
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let suite = "StickersSeasonalRowTests.\(UUID().uuidString)"
        return StickersViewModel(
            subject: .fixture(),
            modelContext: ModelContext(container),
            userId: nil,
            store: StickerStyleStore(defaults: UserDefaults(suiteName: suite)!),
            now: { now }
        )
    }

    private func seasonalItems(_ model: StickersViewModel) -> [StickerItem] {
        model.items.filter { if case .seasonal = $0 { true } else { false } }
    }

    @Test
    func theSeasonalRowLeadsThisClimbInsideItsWindow() throws {
        let model = try makeModel(now: date(2026, 12, 10))
        #expect(!seasonalItems(model).isEmpty)
        #expect(model.items.prefix(seasonalItems(model).count).allSatisfy { if case .seasonal = $0 { true } else { false } })
    }

    @Test
    func outsideEveryWindowTheSeasonalRowIsNotShown() throws {
        for outside in [date(2026, 2, 1), date(2026, 6, 15), date(2026, 9, 30)] {
            let model = try makeModel(now: outside)
            #expect(seasonalItems(model).isEmpty, "a seasonal sticker was offered on \(outside)")
        }
    }
}
