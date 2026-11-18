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
        var telemetry: TelemetryManager = .shared

        var body: some View {
            ShareSheetView(
                source: .workoutDetail,
                workout: workout,
                climb: nil,
                climbRank: presenter.rank,
                climbRankTotal: presenter.total,
                telemetry: telemetry
            )
        }
    }

    private static func activate(_ label: String, in screen: HostedScreen) async throws {
        let elements = try await screen.elements { $0.contains { $0.accessibilityLabel == label } }
        let element = try #require(
            elements.first { $0.accessibilityLabel == label },
            "No \(label) on screen. Found: \(elements.compactMap { $0.accessibilityLabel })"
        )
        #expect(element.accessibilityActivate())
        try await screen.settle()
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

    /// The presenter can rebuild the sheet between the pass that creates its state and the one it
    /// appears on - Workout Detail clears and then re-sets the standing around the Share tap. Every rebuild runs `ShareSheetView.init` again, so a reporter built there and held
    /// in a plain `let` is a fresh one on the copy whose `.task` builds the tab view models, while
    /// the sheet view model keeps the first: edits are tallied on one reporter and the share reads
    /// the other.
    @Test
    func anEditMadeAfterTheStandingRebuildsTheSheetStillRidesOnTheShare() async throws {
        let preferences = PresetPreferencesStore()
        preferences.reset()
        defer { preferences.reset() }

        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let workout = Workout(duration: 3_770, steps: 5_004, floors: 0, source: .headphoneMotion)
        let presenter = Presenter()
        let controller = UIHostingController(
            rootView: Host(workout: workout, presenter: presenter, telemetry: makeTestTelemetry(sink: sink))
                .modelContainer(container)
                .environment(AuthenticationViewModel(observesFirebaseAuth: false))
        )
        // Sizing builds the sheet's state off screen without it appearing, the way a presentation
        // sizes its content first; the standing then rebuilds it before its first `.task` runs.
        _ = controller.sizeThatFits(in: RenderedScreen.iPhone16ProSize)
        presenter.rank = 32
        presenter.total = 85
        _ = controller.sizeThatFits(in: RenderedScreen.iPhone16ProSize)

        try await RenderedScreen.host(controller) { screen in
            _ = try await screen.copy { $0.contains("curve layout") }
            try await Self.activate("Font: closed", in: screen)
            try await Self.activate("Mono font", in: screen)
            try await Self.activate("Copy", in: screen)
        }

        let tap = try #require(sink.records.first { $0.name == "live_climb_share_action_tap" })
        #expect(tap.parameters["edited_font"] == .bool(true), "Read: \(tap.parameters)")
        #expect(tap.parameters["edit_count_bucket"] != .string("zero"), "Read: \(tap.parameters)")
        #expect(sink.records.filter { $0.name == "share_composer_open" }.count == 1)
    }
}
