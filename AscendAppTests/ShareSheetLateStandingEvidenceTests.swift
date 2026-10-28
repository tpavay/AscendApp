import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Share opens the sheet on the frame it was tapped, before Workout Detail or the completion
/// summary has resolved the climb's frozen standing. The standing lands on a sheet already on
/// screen, and the cards have to take it: the Rank stat, the Rank and Curve layouts and the rank
/// stickers all hang off it.
@MainActor
@Suite(.hostsAWindow)
struct ShareSheetLateStandingEvidenceTests {
    @MainActor
    @Observable
    final class Presenter {
        var rank: Int?
        var total: Int?
    }

    private struct Host: View {
        let workout: Workout
        let presenter: Presenter

        var body: some View {
            ShareSheetView(
                workout: workout,
                climb: nil,
                climbRank: presenter.rank,
                climbRankTotal: presenter.total
            )
        }
    }

    @Test
    func aStandingThatLandsAfterTheSheetOpensReachesTheCards() async throws {
        let preferences = PresetPreferencesStore()
        preferences.reset()
        defer { preferences.reset() }

        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let workout = Workout(duration: 3_770, steps: 5_004, floors: 0, source: .headphoneMotion)
        let presenter = Presenter()
        let view = Host(workout: workout, presenter: presenter)
            .modelContainer(container)
            .environment(AuthenticationViewModel(observesFirebaseAuth: false))

        try await RenderedScreen.host(view) { screen in
            // No standing yet: the swipe order holds no layout that needs a rank.
            let before = try await screen.copy { $0.contains("classic layout") }
            #expect(!before.contains("rank layout"), "Read: \(before)")
            #expect(!before.contains("curve layout"), "Read: \(before)")

            presenter.rank = 32
            presenter.total = 85
            try await screen.settle()

            let after = try await screen.copy { $0.contains("curve layout") }
            #expect(after.contains("rank layout"), "the standing landed and the cards never took it. Read: \(after)")
            #expect(after.contains("curve layout"), "Read: \(after)")
        }
    }
}
