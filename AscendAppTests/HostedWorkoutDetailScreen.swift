import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Hosts the shipping `WorkoutDetailView` in the test host app's live window scene.
///
/// A detached window has no display link, so SwiftUI never runs its update loop in one and every
/// measurement taken there reads as free. The scroll-cost drive needs the real scene and a
/// synchronous run-loop settle that `RenderedScreen` deliberately does not offer, so this mounting -
/// and its load-bearing teardown order - stays beside it. It captures nothing: a screen read as
/// facts goes through `RenderedScreen`.
@MainActor
struct HostedWorkoutDetailScreen {
    let window: UIWindow
    let scrollView: UIScrollView

    /// Mounts `workout`'s detail screen, settles it, and hands the caller the live scroll view.
    static func run<Value>(
        for workout: Workout,
        settleFor settleDuration: TimeInterval = 0.6,
        _ body: @MainActor (HostedWorkoutDetailScreen) async throws -> Value
    ) async throws -> Value {
        let container = try makeRetainedContainer()
        container.mainContext.insert(workout)
        try container.mainContext.save()

        let host = UIHostingController(
            rootView: WorkoutDetailView(workout: workout, embedsInNavigationStack: false)
                .environment(AuthenticationViewModel())
                .environment(MediaUploadManager.shared)
                .modelContainer(container)
        )

        let scene = try #require(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "The test host app should expose a live window scene"
        )
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        // Detaching from the scene is what dismantles the content. Hiding is not enough: a window
        // still attached keeps `WorkoutDetailView`'s `@Query` observing SwiftData after this test's
        // container has gone quiet, and that observer then traps on the next save any other suite
        // performs, taking the whole test process down. The dismantling also needs a beat of the
        // run loop before the next save, or that observer hangs the save instead
        // (`RenderedScreen.dismantle` has the measurement).
        func dismantle() async {
            window.isHidden = true
            previousKeyWindow?.makeKey()
            window.rootViewController = nil
            window.windowScene = nil
            for _ in 0..<2 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(20))
            }
        }

        settle(window, for: settleDuration)

        let result: Value
        do {
            let scrollView = try #require(
                firstScrollView(in: window),
                "The no-photo Workout Detail layout should render a ScrollView"
            )
            result = try await body(
                HostedWorkoutDetailScreen(window: window, scrollView: scrollView)
            )
        } catch {
            await dismantle()
            throw error
        }
        await dismantle()
        return result
    }

    /// Runs the render loop far enough that SwiftUI has applied the invalidations the last change
    /// produced, so a caller measures the work rather than the queuing of it.
    func flush() {
        window.layoutIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date())
    }

    /// Gives the run loop wall-clock time, for callers that need the screen fully drawn.
    func settle(for duration: TimeInterval) {
        Self.settle(window, for: duration)
    }

    /// Stays synchronous: `RunLoop.run(until:)` is unavailable from an async context, and the
    /// mounting above needs it before it can hand a settled screen to the caller.
    private static func settle(_ window: UIWindow, for duration: TimeInterval) {
        window.setNeedsLayout()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
        window.layoutIfNeeded()
    }

    func scroll(to offset: CGFloat) {
        scrollView.contentOffset = CGPoint(x: 0, y: offset)
    }

    /// Every scroll offset a climber can reach, first page through last.
    var pageOffsets: [CGFloat] {
        let maximumOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        let pageStride = max(scrollView.bounds.height * 0.7, 1)
        var offsets = Array(stride(from: CGFloat.zero, through: maximumOffset, by: pageStride))
        if offsets.last != maximumOffset {
            offsets.append(maximumOffset)
        }

        return offsets
    }

    /// `WorkoutDetailView` carries a `@Query`, and SwiftUI keeps observing SwiftData for a beat
    /// after the host is torn down. A container that dies with the test is gone before that
    /// observer is, and the observer then traps on the dangling reference the next time *any*
    /// suite calls `ModelContext.save()` - taking the whole test process down with it, attributed
    /// to whatever unrelated code happened to be saving. Each run still gets its own store, so no
    /// suite renders against another's fixtures.
    private static var retainedContainers: [ModelContainer] = []

    private static func makeRetainedContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        retainedContainers.append(container)
        return container
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let found = firstScrollView(in: subview) {
                return found
            }
        }

        return nil
    }
}
