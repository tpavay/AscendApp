import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing photographs of the Climb Detail overview after the worded headphone card
/// was deleted.
///
/// `ClimbDetailHeadphoneAffordanceTests` proves the route to the compatible-headphones list
/// survived by reading the accessibility tree; this suite puts the same hosted screen in front
/// of a camera so a reviewer sees what a climber sees: no "How it works" card above the CTA,
/// and an icon-only `headphones` control square with, and level with, Start Live Climb - at the
/// default text size and at an accessibility one - opening the same device list on tap.
///
/// Images land in `ASCEND_EVIDENCE_DIR` when it is set and in the test host's temporary
/// directory otherwise; the path is logged either way. Nothing reads them back - these are
/// evidence, not golden-image assertions.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ClimbDetailHeadphoneAffordanceEvidenceTests {
    private static let screenSize = CGSize(width: 393, height: 852)
    private static let headphoneControlLabel = "Compatible headphones"

    /// The same catalogue-of-one and from-memory board the affordance suite uses, for the same
    /// reason: hosting the real screen must not take a dependency on a deploy or on whichever
    /// Firebase project the test host points at.
    private static let catalogService = ClimbService(
        catalogRepository: StubClimbCatalogRepository(climbs: [.preview])
    )

    private static let leaderboardService = StubLiveReplayLeaderboardService(
        completionLeaderboard: .empty
    )

    private static let container: ModelContainer? = try? ModelContainer(
        for: Workout.self,
        WorkoutSourceLink.self,
        WorkoutParticipation.self,
        ClimbAttempt.self,
        BestEffortCacheEntry.self,
        BestEffortCacheMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    @Test("The overview is photographed with the glyph beside Start Live Climb and no worded card")
    func theOverviewIsPhotographed() async throws {
        try await withHostedClimbDetail(dynamicTypeSize: .large) { window in
            let labels = try await settledLabels(under: window)
            #expect(labels.contains(Self.headphoneControlLabel))
            #expect(!labels.contains { $0.contains("How it works") })

            try await photograph(window, named: "climb-detail-1-overview-default-text")

            try await scrollToBottom(in: window)
            try await photograph(window, named: "climb-detail-2-action-row-default-text")
        }
    }

    @Test("The control is photographed staying square and level at an accessibility text size")
    func theControlIsPhotographedAtAccessibilityTextSize() async throws {
        try await withHostedClimbDetail(dynamicTypeSize: .accessibility3) { window in
            let labels = try await settledLabels(under: window)
            #expect(labels.contains(Self.headphoneControlLabel))

            try await scrollToBottom(in: window)
            try await photograph(window, named: "climb-detail-3-action-row-accessibility3-text")
        }
    }

    @Test("Tapping the glyph is photographed opening the compatible-headphones list")
    func theListIsPhotographedOpening() async throws {
        try await withHostedClimbDetail(dynamicTypeSize: .large) { window in
            _ = try await settledLabels(under: window)
            try await scrollToBottom(in: window)

            try activateAccessibilityElement(labelled: Self.headphoneControlLabel, in: window)

            // The sheet is a separate presentation, so wait for its copy rather than the
            // screen's: the list is what the deleted card's "How it works" used to open.
            let presented = try await settledAccessibilityElements(under: window) { elements in
                elements.contains { $0.accessibilityLabel?.contains("AirPods Pro 2") == true }
            }
            #expect(presented.compactMap(\.accessibilityLabel).contains { $0.contains("AirPods Pro 2") })

            try await photograph(window, named: "climb-detail-4-compatible-headphones-sheet")
        }
    }

    // MARK: - Hosting

    private func settledLabels(under root: UIView) async throws -> [String] {
        try await settledAccessibilityElements(under: root) { elements in
            elements.contains { $0.accessibilityLabel == Self.headphoneControlLabel }
        }
        .compactMap(\.accessibilityLabel)
    }

    /// The race action sits at the foot of the overview page, so the camera has to travel the
    /// way a climber's thumb does before it can see it.
    private func scrollToBottom(in root: UIView) async throws {
        guard let scrollView = firstScrollView(under: root) else {
            Issue.record("Climb Detail published no scroll view to travel")
            return
        }

        for _ in 0..<8 {
            root.setNeedsLayout()
            root.layoutIfNeeded()
            let maximum = max(
                0,
                scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            )
            scrollView.setContentOffset(CGPoint(x: 0, y: maximum), animated: false)
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func firstScrollView(under root: UIView) -> UIScrollView? {
        if let scrollView = root as? UIScrollView { return scrollView }

        for subview in root.subviews {
            if let found = firstScrollView(under: subview) { return found }
        }

        return nil
    }

    private func photograph(_ window: UIWindow, named name: String) async throws {
        for _ in 0..<8 {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)

        #expect(png.count > 5_000)
        print("Rendered Climb Detail headphone evidence: \(url.path())")
    }

    private func withHostedClimbDetail(
        dynamicTypeSize: DynamicTypeSize,
        _ whileOnScreen: (UIWindow) async throws -> Void
    ) async throws {
        let container = try #require(Self.container, "This suite needs an in-memory container")

        try await withAccessibilityAutomation {
            let host = UIHostingController(
                rootView: NavigationStack {
                    ClimbDetailView(
                        climb: .preview,
                        climbService: Self.catalogService,
                        leaderboardService: Self.leaderboardService
                    )
                }
                .modelContainer(container)
                .environment(ModerationStore.shared)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
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
