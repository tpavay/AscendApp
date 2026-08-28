import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The compatible-headphones list stayed reachable when its worded card was deleted.
///
/// The card ("Your headphones track your steps, not a watch or phone." + "How it works")
/// was a permanent paragraph on the one screen that exists to start a race. It is a glyph
/// beside Start Live Climb now - but the requirement behind it is real, so the route to the
/// device list may never be lost, and it has to keep an assistive-technology label and hint
/// equivalent to the ones the card carried.
///
/// This drives the real `ClimbDetailView` in a live window scene rather than reproducing its
/// layout: a copy of the view cannot notice the day someone deletes the control.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ClimbDetailHeadphoneAffordanceTests {
    private static let screenSize = CGSize(width: 393, height: 852)

    /// A catalogue of exactly the climb under test, not `ClimbService.shared`: the test host
    /// launches the real app, whose singleton refreshes from the environment's hosted
    /// catalogue and would make this suite depend on a deploy.
    private static let catalogService = ClimbService(
        catalogRepository: StubClimbCatalogRepository(climbs: [.preview])
    )

    /// Held for the process, not per render: the detail screen keeps observing SwiftData for a
    /// beat after its host is torn down, and a container that has already gone traps on the
    /// next fetch any other suite performs.
    private static let container: ModelContainer? = try? ModelContainer(
        for: Workout.self,
        WorkoutSourceLink.self,
        WorkoutParticipation.self,
        ClimbAttempt.self,
        BestEffortCacheEntry.self,
        BestEffortCacheMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    @Test("Climb Detail publishes a labelled route to the compatible-headphones list")
    func theCompatibleHeadphonesControlIsReachable() async throws {
        try await withHostedClimbDetail { root in
            let elements = accessibilityElements(under: root)
            let control = elements.first { $0.accessibilityLabel == "Compatible headphones" }

            let onScreen = elements.compactMap(\.accessibilityLabel)
            let found = try #require(
                control,
                "Climb Detail must keep a route to the compatible-headphones list. On screen: \(onScreen)"
            )
            #expect(found.accessibilityHint == "Opens the compatible headphones list.")
        }
    }

    @Test("The worded tracking card is gone from the overview")
    func theTrackingExplainerCardIsNotOnScreen() async throws {
        try await withHostedClimbDetail { root in
            let labels = accessibilityElements(under: root).compactMap(\.accessibilityLabel)

            // The card's own copy, and the phrase that made it read as a manual.
            #expect(!labels.contains { $0.contains("How it works") })
            #expect(!labels.contains { $0.contains("track your steps") })
        }
    }

    // MARK: - Hosting

    /// Climb Detail needs a live window: it sits in a `NavigationStack`, which `ImageRenderer`
    /// cannot flatten, and its content only resolves once SwiftUI has run an update loop
    /// against a real display link.
    private func withHostedClimbDetail(
        _ whileOnScreen: (UIView) async throws -> Void
    ) async throws {
        let container = try #require(Self.container, "This suite needs an in-memory container")

        try await withAccessibilityAutomation {
            let host = UIHostingController(
                rootView: NavigationStack {
                    ClimbDetailView(climb: .preview, climbService: Self.catalogService)
                }
                .modelContainer(container)
                .environment(ModerationStore.shared)
                .preferredColorScheme(.dark)
            )

            let scene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
                "test host app should expose a live UIWindowScene"
            )
            let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: Self.screenSize)
            window.overrideUserInterfaceStyle = .dark
            window.backgroundColor = .black
            window.rootViewController = host

            defer {
                window.isHidden = true
                previousKeyWindow?.makeKey()
                window.rootViewController = nil
                window.windowScene = nil
            }

            window.makeKeyAndVisible()
            for _ in 0..<12 {
                window.setNeedsLayout()
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(50))
            }

            try await whileOnScreen(window)
        }
    }
}
