import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Hosts the real climb detail screen - `WorkoutDetailView` itself, not a stand-in for its
/// stack - for a climb the cloud refused and for one that landed, and photographs each under
/// `ASCEND_EVIDENCE_DIR`.
///
/// Every other test of this row substitutes something for the screen: the hosting suite mounts the
/// section as a root view, and the nesting test rebuilds the detail screen's `spacing: 24` stack by
/// hand. Both substitutions were once passing while the warning was dead on the screen that ships,
/// so the only measurement that settles it is the screen that ships: host `WorkoutDetailView`, read
/// the `UIScrollView` SwiftUI built for it, and compare the scroll content of a refused climb
/// against a synced one of identical shape.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct WorkoutSyncDetailScreenEvidenceTests {
    @Test
    func theRefusedClimbCarriesTheWarningOnTheRealDetailScreen() async throws {
        let container = try Self.hostedContainer()

        let refused = Self.makeWorkout(name: "CN Tower Live Climb")
        refused.markPendingRemoteUpsert(ownerUserId: "user-123")
        refused.remoteSyncStatus = .rejected

        let landed = Self.makeWorkout(name: "CN Tower Live Climb")
        landed.markPendingRemoteUpsert(ownerUserId: "user-123")
        landed.markRemoteSyncSucceeded(heartRateSeries: nil)

        container.mainContext.insert(refused)
        container.mainContext.insert(landed)
        try container.mainContext.save()

        #expect(
            WorkoutSyncCoordinator.shared.presentation(for: refused) == .couldNotSync,
            "the coordinator has to be offering a warning for this climb, or this measures nothing"
        )
        #expect(
            WorkoutSyncCoordinator.shared.presentation(for: landed) == .hidden,
            "the landed climb has to have nothing to say, or the comparison below is not a control"
        )

        let refusedContent = try await Self.settledScrollContentHeight(
            of: refused,
            in: container,
            capturing: "10-detail-screen-refused",
            caption: "Real WorkoutDetailView, climb the cloud refused"
        )
        let landedContent = try await Self.settledScrollContentHeight(
            of: landed,
            in: container,
            capturing: "11-detail-screen-synced",
            caption: "Real WorkoutDetailView, same climb once it landed - no row, no gap"
        )

        print("ASCEND_DETAIL_SCROLL_CONTENT refused=\(refusedContent)pt synced=\(landedContent)pt")

        #expect(
            refusedContent > landedContent,
            """
            On the real detail screen a refused climb scrolls \(refusedContent)pt against \
            \(landedContent)pt for an identical climb that landed. The sync row is drawing nothing \
            where the screen actually places it, so a climber whose climb the server refused sees \
            no warning and no TRY AGAIN.
            """
        )
    }

    // MARK: - Harness

    /// Hosts the detail screen through `RenderedScreen` - whose teardown detaches the window from
    /// its scene, which is what dismantles the content: a window still attached keeps
    /// `WorkoutDetailView`'s `@Query` observing SwiftData, and that observer traps on the next
    /// save any other suite performs - and returns its scroll content height once pumped.
    private static func settledScrollContentHeight(
        of workout: Workout,
        in container: ModelContainer,
        capturing name: String,
        caption: String
    ) async throws -> CGFloat {
        let host = UIHostingController(
            rootView: WorkoutDetailView(workout: workout, embedsInNavigationStack: false)
                .environment(AuthenticationViewModel())
                .environment(MediaUploadManager.shared)
                .modelContainer(container)
        )

        return try await RenderedScreen.host(host) { screen in
            // Pumped well past any lifecycle the screen might be waiting on, so a row that only
            // ever appears late still appears here - and one that never appears cannot be excused
            // as slow.
            var contentHeight: CGFloat = 0
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(10))
                pump(screen.window)
                contentHeight = firstScrollView(in: screen.window)?.contentSize.height ?? 0
            }

            pump(screen.window)
            if let url = try screen.photograph(named: name) {
                print("ASCEND_EVIDENCE_PNG \(url.path) - \(caption)")
            }
            return contentHeight
        }
    }

    private static func makeWorkout(name: String) -> Workout {
        Workout(
            name: name,
            date: Date(timeIntervalSince1970: 1_780_000_000),
            duration: 2_347,
            steps: 3_042,
            floors: 190,
            stepsPerFloor: 16,
            notes: "",
            source: .manual
        )
    }

    private static func pump(_ window: UIWindow) {
        window.layoutIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date())
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    /// Held for the process for the same reason every other hosting suite holds its own: SwiftUI
    /// keeps observing SwiftData for a beat after a host is torn down.
    private static let container: ModelContainer? = try? ModelContainer(
        for: Workout.self,
        WorkoutSourceLink.self,
        WorkoutParticipation.self,
        WorkoutSyncOutboxEntry.self,
        PendingWorkoutDeletion.self,
        BestEffortCacheEntry.self,
        BestEffortCacheMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    private static func hostedContainer() throws -> ModelContainer {
        try #require(container, "The evidence test needs an in-memory model container")
    }
}
