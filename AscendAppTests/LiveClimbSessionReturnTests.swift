import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// A climber who leaves a running climb and comes back finds the screen they left.
///
/// 2026-10-03, the captain's own phone: 27 minutes into a Just Climb on the Mountain he left
/// Ascend for the Camera, came back through the Live Activity, and found the Just Me page. Two
/// things had to be true at once. The Live Activity tap replaced the session screen that was
/// still up with a second one built from the session, and the screen that had been up was
/// drawing something its session did not say: the session had been built Classic, and only the
/// screen's own copy of the experience said Mountain.
///
/// Both are held here on Classic sessions, which host no RealityKit scene, so they run on CI's
/// virtual Macs (#629). `HomeGlobeSheetEvidenceTests` holds what came before either - the
/// session Home builds is the one the setup sheet asked for - and
/// `AscendMountainSessionEvidenceTests` holds that a Mountain session reopens as the Mountain.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbSessionReturnTests {
    @Test("A Live Activity tap builds no second screen for a session whose screen is up")
    func liveActivityTapLeavesTheOpenSessionScreenAlone() async throws {
        let container = try RetainedModelContainer.inMemory(schema: AscendLocalStore.schema)
        let session = Self.recordingSession(steps: 1_842, container: container)
        // The session's screen is up the way Home and the recovery cover put it up: presented
        // by something other than the route the Live Activity tap takes.
        let screen = ZStack {
            AppNavigationHost()
            NavigationStack {
                LiveClimbSessionView(viewModel: session)
            }
        }
        .environment(AuthenticationViewModel())
        .environment(ModerationStore.shared)
        .environment(NetworkConnectivityService.shared)
        .modelContainer(container)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
            // The climber moves to the Leaderboard, leaves Ascend, and taps the Live Activity.
            try await Self.activate(in: hosted) { Self.isSessionTab($0, titled: "Leaderboard") }
            _ = try await hosted.elements { $0.contains { Self.isSessionTab($0, titled: "Leaderboard", selected: true) } }

            LiveClimbActivityRouter.shared.route(sessionID: session.liveActivitySessionID, climbID: "just-climb")
            try await hosted.settle(.turns(30, interval: .milliseconds(100)))

            let elements = try await hosted.elements { $0.contains { Self.isSessionTab($0, titled: "Leaderboard") } }
            #expect(
                elements.filter { $0.accessibilityLabel == "End attempt" }.count == 1,
                "one session, one screen: the tap built no second one behind the first"
            )
            #expect(
                elements.contains { Self.isSessionTab($0, titled: "Leaderboard", selected: true) },
                "the screen that was up is still up, on the tab the climber chose"
            )
            #expect(
                LiveClimbActivityCommandCenter.shared.isAnswering(sessionID: session.liveActivitySessionID),
                "and it still answers the Live Activity's stop control"
            )
        }
        await session.discard(modelContext: container.mainContext)
    }

    @Test("A Live Activity tap reopens a running session whose screen is gone")
    func liveActivityTapReopensASessionWhoseScreenIsGone() async throws {
        let container = try RetainedModelContainer.inMemory(schema: AscendLocalStore.schema)
        let session = Self.recordingSession(steps: 1_842, container: container)
        let screen = AppNavigationHost()
            .environment(AuthenticationViewModel())
            .environment(ModerationStore.shared)
            .environment(NetworkConnectivityService.shared)
            .modelContainer(container)

        try await RenderedScreen.host(screen, settle: .turns(30, interval: .milliseconds(100))) { hosted in
            #expect(!LiveClimbActivityCommandCenter.shared.isAnswering(sessionID: session.liveActivitySessionID))

            LiveClimbActivityRouter.shared.route(sessionID: session.liveActivitySessionID, climbID: "just-climb")

            let reopened = try await hosted.copy { $0.contains("end attempt") }
            #expect(reopened.contains("1,842"), "the tap is the way back into the running session: \(reopened)")
            #expect(LiveClimbActivityCommandCenter.shared.isAnswering(sessionID: session.liveActivitySessionID))
        }
        await session.discard(modelContext: container.mainContext)
    }

    @Test("The session screen draws the session it holds, whatever it is rebuilt around")
    func sessionScreenDrawsTheSessionItHolds() async throws {
        let container = try RetainedModelContainer.inMemory(schema: AscendLocalStore.schema)
        let held = Self.recordingSession(steps: 1_842, container: container)
        // Never started and never mounted: only handed to the struct on a later pass, the way a
        // presenter's update rebuilds the screen's value while `@State` keeps the first session.
        let other = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            experience: .mountain,
            motionSession: FakeHeadphoneMotionSession(),
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            backgroundSessionService: FakeLiveClimbBackgroundSession()
        )
        let presenter = RebuildingPresenter(first: held, later: other)

        try await RenderedScreen.host(
            RebuildingPresenterView(presenter: presenter)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { hosted in
            let before = try await hosted.copy { $0.contains("end attempt") }
            #expect(before.contains("just me"), "a Classic session draws its tabs: \(before)")

            presenter.rebuild()
            try await hosted.settle(.turns(20, interval: .milliseconds(50)))

            let after = try await hosted.copy { $0.contains("end attempt") }
            #expect(after.contains("just me"), "the screen still draws the session it holds: \(after)")
            #expect(after.contains("1,842"), "\(after)")
        }
        await held.discard(modelContext: container.mainContext)
    }

    // MARK: - Fixtures

    /// A Classic Just Climb that is already recording.
    private static func recordingSession(steps: Int, container: ModelContainer) -> LiveClimbSessionViewModel {
        let motionSession = FakeHeadphoneMotionSession()
        motionSession.stepCount = steps
        motionSession.duration = 504
        let session = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(),
            experience: .classic,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            backgroundSessionService: FakeLiveClimbBackgroundSession()
        )
        session.start(modelContext: container.mainContext)
        return session
    }

    /// One of the live screen's two tabs. The app's own tab bar carries a Leaderboard too, so a
    /// match is a button in the top half of the screen.
    private static func isSessionTab(_ element: NSObject, titled title: String, selected: Bool? = nil) -> Bool {
        guard element.accessibilityLabel == title,
              element.accessibilityTraits.contains(.button),
              element.accessibilityFrame.midY < RenderedScreen.iPhone16ProSize.height / 2 else { return false }
        guard let selected else { return true }
        return element.accessibilityTraits.contains(.selected) == selected
    }

    /// Waits for a control to arrive, then activates it.
    private static func activate(
        in hosted: HostedScreen,
        matching isMatch: @escaping (NSObject) -> Bool
    ) async throws {
        _ = try await hosted.elements { $0.contains(where: isMatch) }
        try activateAccessibilityElement(in: hosted.window, matching: isMatch)
    }
}

/// The app's own nesting: `RootNavigationHost` puts the whole tab view inside an outer stack,
/// which is why a pushed session covers the tab bar.
private struct AppNavigationHost: View {
    @State private var tabRouter = TabRouter()
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            MainTabView(tabRouter: tabRouter)
        }
    }
}

@MainActor
@Observable
private final class RebuildingPresenter {
    private(set) var session: LiveClimbSessionViewModel
    private let later: LiveClimbSessionViewModel

    init(first: LiveClimbSessionViewModel, later: LiveClimbSessionViewModel) {
        session = first
        self.later = later
    }

    func rebuild() {
        session = later
    }
}

private struct RebuildingPresenterView: View {
    let presenter: RebuildingPresenter

    var body: some View {
        NavigationStack {
            LiveClimbSessionView(viewModel: presenter.session)
        }
    }
}
