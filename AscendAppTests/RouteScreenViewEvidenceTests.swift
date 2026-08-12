import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Proves the three things a screen funnel is worthless without: a visit is one event no
/// matter how often the surface redraws, moving between tabs reports the tab arrived at, and
/// a modal closed and opened again is two visits rather than one.
///
/// Hosts real windows, so it takes the same gate every other hosting suite takes.
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

        let window = hostWindow(
            ScreenHarness(screen: .climbDetail, redraws: redraws, telemetry: telemetry)
        )
        defer { teardown(window) }

        let emitted = try await pump(window) { sink.screenCount(of: .climbDetail) == 1 }
        #expect(emitted)

        let before = redraws.count
        redraws.revision += 1
        let rerendered = try await pump(window) { redraws.count > before }
        #expect(rerendered)

        try await drain(window)

        #expect(sink.screenCount(of: .climbDetail) == 1)
        #expect(sink.screens.first?.screenClass == TelemetryScreenName.climbDetail.screenClass)
    }

    /// Switching tabs is the most common navigation in the app, and the one a container-level
    /// event would report exactly once per session.
    @Test
    func switchingTabsReportsTheTabArrivedAt() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let router = TabRouter()

        let window = hostWindow(TabHarness(router: router, telemetry: telemetry))
        defer { teardown(window) }

        #expect(try await pump(window) { sink.screenCount(of: .home) == 1 })

        router.select(.leaderboard, reason: .tabBarTap)
        #expect(try await pump(window) { sink.screenCount(of: .leaderboard) == 1 })

        router.select(.profile, reason: .tabBarTap)
        #expect(try await pump(window) { sink.screenCount(of: .profile) == 1 })

        // Coming back is a visit too: the tab was unmounted while it was hidden.
        router.select(.home, reason: .tabBarTap)
        #expect(try await pump(window) { sink.screenCount(of: .home) == 2 })

        try await drain(window)

        #expect(sink.screenCount(of: .routines) == 0)
        #expect(sink.screens.allSatisfy { $0.name != "main_app" })
    }

    /// The guard belongs to the view instance, so a sheet dismissed and presented again is a
    /// second visit. A guard that outlived the presentation would report a modal opened five
    /// times as one.
    @Test
    func aDismissedSheetReportsAgainWhenItIsPresentedAgain() async throws {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let presentation = SheetPresentation()

        let window = hostWindow(
            SheetHarness(presentation: presentation, telemetry: telemetry)
        )
        defer { teardown(window) }

        presentation.isPresented = true
        #expect(try await pump(window) { sink.screenCount(of: .justClimbSetup) == 1 })

        presentation.isPresented = false
        try await drain(window)
        #expect(sink.screenCount(of: .justClimbSetup) == 1)

        presentation.isPresented = true
        #expect(try await pump(window) { sink.screenCount(of: .justClimbSetup) == 2 })
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
            .onboarding(.displayName),
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

    // MARK: - Rendering

    private func hostWindow(_ view: some View) -> UIWindow {
        let size = CGSize(width: 390, height: 640)
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: controller.view.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return window
    }

    private func teardown(_ window: UIWindow) {
        window.resignKey()
        window.isHidden = true
        window.rootViewController = nil
    }

    /// Drives layout until the condition holds, so a slow machine costs latency rather than a
    /// red build.
    @discardableResult
    private func pump(
        _ window: UIWindow,
        iterations: Int = 200,
        until isSatisfied: () -> Bool
    ) async throws -> Bool {
        for _ in 0..<iterations {
            window.setNeedsLayout()
            window.layoutIfNeeded()

            if isSatisfied() {
                return true
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        return false
    }

    /// A bounded drain for the assertions that something did NOT happen - there is no
    /// condition to wait on, only a window in which it could have.
    private func drain(_ window: UIWindow, iterations: Int = 12) async throws {
        _ = try await pump(window, iterations: iterations) { false }
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
