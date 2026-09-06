import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Proves the three things a screen funnel is worthless without: a visit is one event no
/// matter how often the surface redraws, moving between tabs reports the tab arrived at, and
/// a modal closed and opened again is two visits rather than one.
///
/// Hosts real windows through `RenderedScreen`, so it takes the same gate every other hosting
/// suite takes. Nothing here is photographed: the facts are the events the sink received.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct RouteScreenViewEvidenceTests {

    /// A redraw is not a navigation. State churning behind a mounted route - a filter, a
    /// loaded result, an animation frame - must not bank a second visit.
    @Test
    func aMountedScreenReportsOnceAcrossRerenders() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let redraws = RedrawCounter()

        try await host(
            ScreenHarness(screen: .climbDetail, redraws: redraws, telemetry: telemetry)
        ) { screen in
            let emitted = try await pump(screen) { sink.screenCount(of: .climbDetail) == 1 }
            #expect(emitted)

            let before = redraws.count
            redraws.revision += 1
            let rerendered = try await pump(screen) { redraws.count > before }
            #expect(rerendered)

            try await drain(screen)

            #expect(sink.screenCount(of: .climbDetail) == 1)
            #expect(sink.screens.first?.screenClass == TelemetryScreenName.climbDetail.screenClass)
        }
    }

    /// Switching tabs is the most common navigation in the app, and the one a container-level
    /// event would report exactly once per session.
    @Test
    func switchingTabsReportsTheTabArrivedAt() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let router = TabRouter()

        try await host(TabHarness(router: router, telemetry: telemetry)) { screen in
            #expect(try await pump(screen) { sink.screenCount(of: .home) == 1 })

            router.select(.leaderboard, reason: .tabBarTap)
            #expect(try await pump(screen) { sink.screenCount(of: .leaderboard) == 1 })

            router.select(.profile, reason: .tabBarTap)
            #expect(try await pump(screen) { sink.screenCount(of: .profile) == 1 })

            // Coming back is a visit too: the tab was unmounted while it was hidden.
            router.select(.home, reason: .tabBarTap)
            #expect(try await pump(screen) { sink.screenCount(of: .home) == 2 })

            try await drain(screen)

            #expect(sink.screenCount(of: .routines) == 0)
            #expect(sink.screens.allSatisfy { $0.name != "main_app" })
        }
    }

    /// The guard belongs to the view instance, so a sheet dismissed and presented again is a
    /// second visit. A guard that outlived the presentation would report a modal opened five
    /// times as one.
    @Test
    func aDismissedSheetReportsAgainWhenItIsPresentedAgain() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let presentation = SheetPresentation()

        try await host(
            SheetHarness(presentation: presentation, telemetry: telemetry)
        ) { screen in
            presentation.isPresented = true
            #expect(try await pump(screen) { sink.screenCount(of: .justClimbSetup) == 1 })

            // A real presentation takes a real dismissal: re-presenting before the modal is gone
            // is a state the climber cannot reach, and UIKit swallows it.
            presentation.isPresented = false
            #expect(
                try await pump(screen) {
                    screen.window.rootViewController?.presentedViewController == nil
                }
            )

            try await drain(screen)
            #expect(sink.screenCount(of: .justClimbSetup) == 1)

            presentation.isPresented = true
            #expect(try await pump(screen) { sink.screenCount(of: .justClimbSetup) == 2 })
        }
    }

    /// Entering the app is the first hop of every session, and the one route change that lands
    /// on a container: `.mainApp` reports nothing itself, so the tab it mounts is the only
    /// thing that can report the arrival. Tab-to-tab switching cannot cover this - the tab
    /// container is already mounted by then.
    @Test
    func arrivingInTheAppFromTheGateReportsTheFirstTab() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let route = RouteBox()

        try await host(RouteHarness(route: route, telemetry: telemetry)) { screen in
            #expect(try await pump(screen) { sink.screenCount(of: .appAccessGate) == 1 })

            route.route = .mainApp
            #expect(try await pump(screen) { sink.screenCount(of: .home) == 1 })

            try await drain(screen)

            // The gate is behind the climber, and the container it handed off to is not a screen.
            #expect(sink.screenCount(of: .home) == 1)
            #expect(sink.screenCount(of: .appAccessGate) == 1)
            #expect(sink.screens.allSatisfy { $0.name != "main_app" })
        }
    }

    /// Every root route resolves to a decision, and the container resolves to no event.
    @Test
    func everyRootRouteResolvesToAReviewedScreenExceptTheContainer() {
        let routes: [AppRootRoute] = [
            .updateRequired,
            .signedOut,
            .signingIn,
            .restoringSession,
            .resolving,
            .onboarding(.stairStepperBaseline),
            .paywall,
            .mainApp
        ]

        for route in routes where route != .mainApp {
            #expect(route.telemetryScreenName != nil, "\(route) has no screen")
        }

        #expect(AppRootRoute.mainApp.telemetryScreenName == nil)
        #expect(AppRootRoute.paywall.telemetryScreenName == .appAccessGate)
        #expect(AppRootRoute.onboarding(.gender).telemetryScreenName == .onboardingFlow)
    }

    @Test
    func everyTabResolvesToItsOwnScreen() {
        let names = [AppTab.home, .training, .leaderboard, .profile].map(\.telemetryScreenName)

        #expect(names == [.home, .routines, .leaderboard, .profile])
        #expect(Set(names).count == names.count)
    }

    // MARK: - Hosting

    /// `RenderedScreen` borrows the host's window scene rather than standing a scene-less
    /// window up.
    ///
    /// Not cosmetic: a window off the scene never mounts a `TabView` that *arrives* after the
    /// first render - no tab bar controller, no tab root, no `body` call - while one that was
    /// there from the first render mounts fine. That asymmetry reads as a missing screen view
    /// on the app's most common entry, and it cost this suite a false alarm once already.
    private func host(
        _ view: some View,
        _ body: @MainActor (HostedScreen) async throws -> Void
    ) async throws {
        try await RenderedScreen.host(
            view,
            size: CGSize(width: 390, height: 640),
            settle: .turns(1),
            body
        )
    }

    /// Drives layout until the condition holds, so a slow machine costs latency rather than a
    /// red build.
    @discardableResult
    private func pump(
        _ screen: HostedScreen,
        iterations: Int = 200,
        until isSatisfied: () -> Bool
    ) async throws -> Bool {
        for _ in 0..<iterations {
            screen.window.setNeedsLayout()
            screen.window.layoutIfNeeded()

            if isSatisfied() {
                return true
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        return false
    }

    /// A bounded drain for the assertions that something did NOT happen - there is no
    /// condition to wait on, only a window in which it could have.
    private func drain(_ screen: HostedScreen, iterations: Int = 12) async throws {
        _ = try await pump(screen, iterations: iterations) { false }
    }
}

// MARK: - Harnesses

/// Deliberately outside observation for `count`: the once-per-appearance assertions are
/// vacuous unless the harness proves a second render actually happened.
@MainActor
@Observable
private final class RedrawCounter {
    var revision = 0
    @ObservationIgnored private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
@Observable
private final class SheetPresentation {
    var isPresented = false
}

@MainActor
@Observable
private final class RouteBox {
    var route: AppRootRoute = .paywall
}

/// Reproduces `RootView`'s route composition around the tab container: the `Group` over a
/// switch, the crossfade the route change animates through, and the screen attached *inside*
/// each branch through the shipped `AppRootRoute` mapping - so `.mainApp` contributes no event
/// and the tab has to report the arrival itself.
///
/// `RootView` proper needs an authenticated session and a resolved entitlement to reach these
/// two routes; the shape it is being held to is the modifier placement, which is reproduced
/// exactly.
private struct RouteHarness: View {
    @Bindable var route: RouteBox
    let telemetry: TelemetryManager
    let router = TabRouter()

    var body: some View {
        Group {
            switch route.route {
            case .paywall:
                routeScreen(.paywall) {
                    Color.clear.frame(width: 390, height: 640)
                }
            case .mainApp:
                routeScreen(.mainApp) {
                    TabHarness(router: router, telemetry: telemetry)
                }
            default:
                Color.clear
            }
        }
        .animation(.easeInOut(duration: 0.25), value: route.route)
    }

    @ViewBuilder
    private func routeScreen(
        _ route: AppRootRoute,
        @ViewBuilder content: () -> some View
    ) -> some View {
        if let screen = route.telemetryScreenName {
            content().trackOnce(screen: screen, telemetry: telemetry)
        } else {
            content()
        }
    }
}

private struct ScreenHarness: View {
    let screen: TelemetryScreenName
    let redraws: RedrawCounter
    let telemetry: TelemetryManager

    var body: some View {
        let _ = redraws.record()

        // The height consumes the observed value, so the redraw is a real dependency rather
        // than a load the compiler is free to drop.
        Color.clear
            .frame(width: 100, height: CGFloat(100 + redraws.revision))
            .trackOnce(screen: screen, telemetry: telemetry)
    }
}

/// Hosts the shipped `MainTabView` shape - the same `TabView(selection:)`, the same binding
/// indirection that writes back through `TabRouter.select`, the same mount guard that leaves
/// hidden tabs unmounted, and the same `.tag` / `.tabItem` / `.toolbar` chain around the
/// tracking modifier. Only the tab roots are stubbed, so the test needs no model container.
///
/// Proving the pattern instead of the shipped view is a failure mode this subsystem has
/// already paid for: driving `TabRouter` directly hid a real binding defect.
private struct TabHarness: View {
    let router: TabRouter
    let telemetry: TelemetryManager

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { router.select($0, reason: .appRouting) }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            ForEach(TabItem.activeTabs) { tab in
                if tab.identifier == router.selectedTab {
                    Color.clear
                        .frame(width: 100, height: 100)
                        .trackOnce(screen: tab.identifier.telemetryScreenName, telemetry: telemetry)
                        .tag(tab.identifier)
                        .tabItem {
                            Text(tab.title)
                        }
                        .toolbar(.hidden, for: .tabBar)
                }
            }
        }
    }
}

private struct SheetHarness: View {
    @Bindable var presentation: SheetPresentation
    let telemetry: TelemetryManager

    var body: some View {
        Color.clear
            .frame(width: 320, height: 560)
            .sheet(isPresented: $presentation.isPresented) {
                Color.clear
                    .trackOnce(screen: .justClimbSetup, telemetry: telemetry)
            }
    }
}

private extension InMemoryTelemetrySink {
    func screenCount(of screen: TelemetryScreenName) -> Int {
        screens.filter { $0.name == screen.rawValue }.count
    }
}
