import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// The Strava card on the shipping Integrations screen, in each state the
/// server can put it in. A climber the server has not allowed sees no Strava
/// at all; an allowed one sees Strava's own Connect button; a connected one sees
/// who they connected as. Photographs are written only under
/// `ASCEND_EVIDENCE_DIR`.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct StravaIntegrationCardEvidenceTests {

    @Test("A climber the server has not allowed sees no Strava card")
    func hiddenForEveryoneElse() async throws {
        try await hostIntegrations(status: .hidden) { screen in
            let copy = try await screen.copy { $0.contains("heart rate monitor") }
            #expect(!copy.contains("strava"))
            try screen.photograph(named: "strava-1-hidden")
        }
    }

    @Test("An allowed climber sees what is sent and Strava's own Connect button")
    func availableShowsConnect() async throws {
        let status = StravaConnectionStatus(isAvailable: true, isConnected: false, athleteName: nil)
        try await hostIntegrations(status: status) { screen in
            let copy = try await screen.copy { $0.contains("connect with strava") }
            #expect(copy.contains("not connected"))
            #expect(copy.contains("including any from apple health"))
            #expect(copy.contains("deletes its access when you disconnect"))
            #expect(!copy.contains("manage, strava"))
            let button = try #require(try await screen.frame(ofElementLabelled: "Connect with Strava"))
            #expect(abs(button.height - 48) < 1, "Strava's button must render at its specified 48pt height")
            #expect(button.maxX <= screen.bounds.width - 20, "the Connect button must sit inside the card")
            try screen.photograph(named: "strava-2-available")
        }
    }

    @Test("A connected climber sees who they connected as, and no Connect button")
    func connectedShowsAthlete() async throws {
        let status = StravaConnectionStatus(isAvailable: true, isConnected: true, athleteName: "Elias M.")
        try await hostIntegrations(status: status) { screen in
            let copy = try await screen.copy { $0.contains("connected · elias m.") }
            #expect(copy.contains("manage"))
            #expect(!copy.contains("connect with strava"))
            try screen.photograph(named: "strava-3-connected")

            try activateAccessibilityElement(in: screen.window) { $0.accessibilityLabel == "Manage" }
            try await screen.settle(.turns(30))
            let sheet = try await screen.copy { $0.contains("disconnect strava") }
            #expect(sheet.contains("view on strava"))
            #expect(sheet.contains("deletes everything it holds from strava"))
            try screen.photograph(named: "strava-4-manage-sheet")
        }
    }

    private func hostIntegrations(
        status: StravaConnectionStatus,
        _ body: @MainActor (HostedScreen) async throws -> Void
    ) async throws {
        let viewModel = StravaIntegrationViewModel(
            client: FakeStravaIntegrationClient(status: status),
            presenter: FakeStravaAuthorizationPresenter()
        )
        let container = try ModelContainer(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let screen = NavigationStack {
            IntegrationsView(strava: viewModel)
        }
        .modelContainer(container)
        try await RenderedScreen.host(screen, settle: .turns(20), body)
    }
}
