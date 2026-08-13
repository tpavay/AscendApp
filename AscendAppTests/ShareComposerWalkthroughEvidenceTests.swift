import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
@Suite(.serialized, .hostsAWindow)
struct ShareComposerWalkthroughEvidenceTests {
    private static let screenSize = CGSize(width: 393, height: 852)

    @Test(.bug(id: 491))
    func fourMarksAreRenderedAgainstTheirRealTargets() async throws {
        let defaultsSuite = "ShareComposerWalkthroughEvidenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let workout = ShareStatClusterPresetTests.recordedWorkout(
            name: "Live Climb",
            trackingMode: .liveClimb,
            climbId: Climb.preview.id,
            heartRate: true
        )
        context.insert(workout)
        try context.save()

        let composer = ShareComposerView(
            workout: workout,
            climb: .preview,
            liveClimbRank: 4,
            liveClimbRankTotal: 1_284,
            walkthroughStore: ShareComposerWalkthroughStore(defaults: defaults)
        )
        .modelContainer(container)
        .transaction { $0.disablesAnimations = true }

        try await withAccessibilityAutomation {
            let controller = UIHostingController(rootView: composer)
            controller.overrideUserInterfaceStyle = .dark
            controller.view.frame = CGRect(origin: .zero, size: Self.screenSize)

            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            let window = scene.map { UIWindow(windowScene: $0) }
                ?? UIWindow(frame: CGRect(origin: .zero, size: Self.screenSize))
            window.frame = CGRect(origin: .zero, size: Self.screenSize)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }

            try await settle(window, title: ShareComposerCoachMark.sources.title)
            try Self.photograph(window, named: "01-source-tabs")

            try activateAccessibilityElement(labelled: "Next", in: window)
            try await settle(window, label: "Presets")
            try activateAccessibilityElement(labelled: "Presets", in: window)
            try await settle(window, label: Climb.preview.name)
            try activateAccessibilityElement(in: window) {
                $0.accessibilityLabel == Climb.preview.name && $0.accessibilityTraits.contains(.button)
            }

            try await settle(
                window,
                title: ShareComposerCoachMark.stats.title,
                previousTitle: ShareComposerCoachMark.sources.title
            )
            try Self.photograph(window, named: "02-stats-sheet")

            try activateAccessibilityElement(labelled: "Next", in: window)
            try await scrollToCompatibleStat(in: window)
            try activateAccessibilityElement(in: window) {
                $0.accessibilityLabel?.hasSuffix("STEPS") == true
                    && $0.accessibilityTraits.contains(.button)
            }

            try await settle(
                window,
                title: ShareComposerCoachMark.editRail.title,
                previousTitle: ShareComposerCoachMark.stats.title,
                waitsForSheetDismissal: true
            )
            try Self.photograph(window, named: "03-edit-rail")

            try activateAccessibilityElement(labelled: "Next", in: window)
            try await settle(
                window,
                title: ShareComposerCoachMark.filters.title,
                previousTitle: ShareComposerCoachMark.editRail.title
            )
            try Self.photograph(window, named: "04-filters")
        }
    }

    @Test(.bug(id: 491))
    func directRecapWaitsForAddStatsBeforePresentingTheStatsMark() async throws {
        let fixture = try makeFixture(named: "DirectRecap")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let recap = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 390, height: 844)))
        }
        let composer = ShareComposerView(
            workout: fixture.workout,
            climb: .preview,
            initialBackground: .recap(recap),
            walkthroughStore: ShareComposerWalkthroughStore(defaults: fixture.defaults)
        )
        .modelContainer(fixture.container)
        .transaction { $0.disablesAnimations = true }

        try await withHostedWindow(composer) { window in
            let composerElements = try await settledAccessibilityElements(under: window) { elements in
                elements.contains { $0.accessibilityLabel == "Add stats" }
            }
            #expect(
                composerElements.contains {
                    ShareComposerCoachMark.allCases.map(\.title).contains($0.accessibilityLabel ?? "")
                } == false
            )
            #expect(
                composerElements.contains {
                    $0.accessibilityLabel == "Climb" && $0.accessibilityTraits.contains(.button)
                } == false
            )

            try activateAccessibilityElement(labelled: "Add stats", in: window)
            try await settle(window, title: ShareComposerCoachMark.stats.title)
        }
    }

    @Test(.bug(id: 491))
    func nonClimbPickerShowsAndDescribesOnlyCameraRoll() async throws {
        let fixture = try makeFixture(named: "NonClimb")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let expectedTitle = ShareComposerSourceOptions.cameraRollOnly.title
        let composer = ShareComposerView(
            workout: fixture.workout,
            walkthroughStore: ShareComposerWalkthroughStore(defaults: fixture.defaults)
        )
        .modelContainer(fixture.container)
        .transaction { $0.disablesAnimations = true }

        try await withHostedWindow(composer) { window in
            try await settle(window, title: expectedTitle)
            try Self.photograph(window, named: "05-non-climb-source")
            try activateAccessibilityElement(labelled: "Next", in: window)
            try await settle(window, label: "Camera Roll")
            let elements = accessibilityElements(under: window)
            #expect(elements.contains { $0.accessibilityLabel == "Camera Roll" })
            #expect(elements.contains { $0.accessibilityLabel == "Presets" } == false)
            #expect(elements.contains { $0.accessibilityLabel == "Recaps" } == false)
        }
    }

    private func settle(
        _ window: UIWindow,
        title: String,
        previousTitle: String? = nil,
        waitsForSheetDismissal: Bool = false
    ) async throws {
        try await settle(window) { elements in
            let currentIsPresent = elements.contains { $0.accessibilityLabel == title }
            let previousIsAbsent = previousTitle.map { previous in
                elements.contains { $0.accessibilityLabel == previous } == false
            } ?? true
            let sheetIsDismissed = !waitsForSheetDismissal
                || window.rootViewController?.presentedViewController == nil
            return currentIsPresent && previousIsAbsent && sheetIsDismissed
        }
        try await settleVisibleCoachMark(in: window, title: title)
    }

    private func settle(
        _ window: UIWindow,
        label: String
    ) async throws {
        try await settle(window) { elements in
            elements.contains { $0.accessibilityLabel == label }
        }
    }

    private func settle(
        _ window: UIWindow,
        until ready: ([NSObject]) -> Bool
    ) async throws {
        _ = try await settledAccessibilityElements(under: window, until: ready)
        window.setNeedsLayout()
        window.layoutIfNeeded()
    }

    /// SwiftUI publishes the incoming overlay's accessibility nodes before its opacity transition
    /// is visually complete. Wait for the heading's frame to remain stable across two rendered
    /// layout passes so screenshots cannot capture a transparent incoming card.
    private func settleVisibleCoachMark(in window: UIWindow, title: String) async throws {
        var previousFrame: CGRect?
        var stableReads = 0

        _ = try await settledAccessibilityElements(under: window) { elements in
            guard let heading = elements.first(where: { $0.accessibilityLabel == title }),
                  window.bounds.intersects(heading.accessibilityFrame) else {
                previousFrame = nil
                stableReads = 0
                return false
            }

            if previousFrame == heading.accessibilityFrame {
                stableReads += 1
            } else {
                previousFrame = heading.accessibilityFrame
                stableReads = 0
            }
            return stableReads >= 2 && !Self.hasActiveOpacityAnimation(in: window.layer)
        }
    }

    private static func hasActiveOpacityAnimation(in layer: CALayer) -> Bool {
        if layer.animationKeys()?.contains(where: { $0.localizedStandardContains("opacity") }) == true {
            return true
        }
        return layer.sublayers?.contains(where: hasActiveOpacityAnimation) == true
    }

    private func makeFixture(named name: String) throws -> HostedFixture {
        let suiteName = "ShareComposerWalkthroughEvidenceTests-\(name)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let workout = ShareStatClusterPresetTests.recordedWorkout(
            name: "Live Climb",
            trackingMode: .liveClimb,
            climbId: Climb.preview.id,
            heartRate: true
        )
        container.mainContext.insert(workout)
        try container.mainContext.save()
        return HostedFixture(
            suiteName: suiteName,
            defaults: defaults,
            container: container,
            workout: workout
        )
    }

    private func withHostedWindow<Content: View>(
        _ content: Content,
        body: (UIWindow) async throws -> Void
    ) async throws {
        try await withAccessibilityAutomation {
            let controller = UIHostingController(rootView: content)
            controller.overrideUserInterfaceStyle = .dark
            controller.view.frame = CGRect(origin: .zero, size: Self.screenSize)
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            let window = scene.map { UIWindow(windowScene: $0) }
                ?? UIWindow(frame: CGRect(origin: .zero, size: Self.screenSize))
            window.frame = CGRect(origin: .zero, size: Self.screenSize)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }
            try await body(window)
        }
    }

    /// Pages the real SwiftUI sheet until its lazy stat grid has materialized an individual stat.
    ///
    /// `accessibilityScroll` does not move a SwiftUI `ScrollView`, so drive its backing scroll view
    /// directly and let SwiftUI publish the accessibility nodes for each newly visible page.
    private func scrollToCompatibleStat(in window: UIWindow) async throws {
        let scrollView = try #require(
            verticalScrollViews(under: window).max {
                verticalOverflow(of: $0) < verticalOverflow(of: $1)
            },
            "The stats sheet did not publish a vertically scrollable view"
        )
        let maximumOffset = max(
            0,
            scrollView.contentSize.height
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
        )
        let pageDistance = max(44, scrollView.bounds.height * 0.7)
        var offset = scrollView.contentOffset.y

        while true {
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: min(offset, maximumOffset)),
                animated: false
            )
            window.setNeedsLayout()
            window.layoutIfNeeded()

            let elements = try await settledAccessibilityElements(
                under: window,
                reading: 12
            ) { elements in
                elements.contains(where: isCompatibleStatButton)
            }
            if elements.contains(where: isCompatibleStatButton) {
                return
            }
            guard offset < maximumOffset else {
                Issue.record("No individual STEPS stat became visible while paging the stats sheet")
                return
            }

            offset = min(offset + pageDistance, maximumOffset)
        }
    }

    private func verticalScrollViews(under root: UIView) -> [UIScrollView] {
        var scrollViews: [UIScrollView] = []

        func visit(_ view: UIView) {
            if let scrollView = view as? UIScrollView,
               verticalOverflow(of: scrollView) > 1,
               !scrollView.isHidden,
               scrollView.alpha > 0 {
                scrollViews.append(scrollView)
            }
            view.subviews.forEach(visit)
        }

        visit(root)
        return scrollViews
    }

    private func verticalOverflow(of scrollView: UIScrollView) -> CGFloat {
        scrollView.contentSize.height
            + scrollView.adjustedContentInset.top
            + scrollView.adjustedContentInset.bottom
            - scrollView.bounds.height
    }

    private func isCompatibleStatButton(_ element: NSObject) -> Bool {
        element.accessibilityLabel?.hasSuffix("STEPS") == true
            && element.accessibilityTraits.contains(.button)
    }

    private static func photograph(_ window: UIWindow, named name: String) throws {
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
        print("evidence: \(url.path())")
    }
}

@MainActor
private struct HostedFixture {
    let suiteName: String
    let defaults: UserDefaults
    let container: ModelContainer
    let workout: Workout
}
