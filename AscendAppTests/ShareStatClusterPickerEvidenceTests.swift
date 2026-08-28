import Foundation
import Observation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The clusters photographed on the surface a climber taps them from.
///
/// `ShareStatClusterPresetEvidenceTests` exports what the shared image looks
/// like; nothing there shows the picker itself. This hosts the shipping
/// `ShareComposerView` in a phone-sized window, walks it the way a climber does
/// - pick a background, the add sheet opens on its own - and photographs the
/// GROUPS grid, then taps a group and photographs the canvas it lands on.
///
/// The screens are the real ones: no stand-in sheet, no re-implemented tile.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ShareStatClusterPickerEvidenceTests {
    private static let screenSize = CGSize(width: 393, height: 852)

    @Test
    func theGroupsPickerAndAPlacedClusterArePhotographed() async throws {
        let defaultsSuite = "ShareStatClusterPickerEvidenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let walkthroughStore = ShareComposerWalkthroughStore(defaults: defaults)
        walkthroughStore.markSeen()

        let container = try Self.makeContainer()
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
            climbRank: 4,
            climbRankTotal: 1_284,
            walkthroughStore: walkthroughStore
        )
        .modelContainer(container)

        try await hostComposer(composer) { window, _ in
            try await openTheAddSheet(in: window)

            // A tile reads out everything it draws and ends on its own name, so
            // the labels below are also what a VoiceOver climber hears.
            let sheetLabels = try await settledAccessibilityElements(under: window) {
                $0.contains { $0.accessibilityLabel?.hasSuffix("HERO") == true }
            }.compactMap(\.accessibilityLabel)
            #expect(
                ["HERO", "RANK", "ROW", "SPLITS", "RECEIPT", "MINIMAL",
                 "HR HERO", "HR ROW", "FULL GRID", "HR MINIMAL"].allSatisfy { title in
                    sheetLabels.contains { $0.hasSuffix(title) }
                },
                "the add sheet did not show every group. Saw: \(sheetLabels)"
            )
            try Self.photograph(window, named: "share-cluster-picker-1-groups-grid")

            // Tapping a group drops it on the canvas as one sticker.
            try activateAccessibilityElement(in: window) {
                $0.accessibilityLabel?.hasSuffix(", SPLITS") == true
            }
            try await settle(window, seconds: 1.0)
            try Self.photograph(window, named: "share-cluster-picker-2-splits-placed")
        }
    }

    /// The captain's report, walked on the surface he walked it on: a saved Empire State climb
    /// opened from Workout Detail, whose rank the completion summary had already resolved.
    ///
    /// What runs here is the Share tap's own seed - the frozen `completionSnapshots` document
    /// staging holds for that climb, read synchronously and network-free through
    /// `SavedClimbShareStanding.stored` - handed to the shipping composer before it draws, and the
    /// assertion is the tile list he enumerated. A device that already holds the snapshot therefore
    /// never shows a rank-less frame at all. It does not exercise `WorkoutDetailView` itself; what
    /// stops a new entry point from silently dropping rank again is that `ShareComposerView`'s rank
    /// parameters carry no defaults, so omitting them is a compile error.
    @Test
    func aSavedClimbOpenedFromWorkoutDetailStillOffersItsRankCluster() async throws {
        let defaultsSuite = "ShareStatClusterPickerEvidenceTests-saved-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let walkthroughStore = ShareComposerWalkthroughStore(defaults: defaults)
        walkthroughStore.markSeen()

        let frozenStore = FrozenCompletionRankStore(defaults: defaults)
        let workoutId = UUID()
        let standing = Self.storedStanding(workoutId: workoutId, in: frozenStore)

        let container = try Self.makeContainer()
        let workout = ShareStatClusterPresetTests.recordedWorkout(
            name: "Empire State Building",
            trackingMode: .liveClimb,
            climbId: Climb.preview.id,
            heartRate: true,
            recordedSteps: 1_576
        )
        container.mainContext.insert(workout)
        try container.mainContext.save()

        let composer = ShareComposerView(
            workout: workout,
            climb: .preview,
            climbRank: standing?.rank,
            climbRankTotal: standing?.totalClimbers,
            walkthroughStore: walkthroughStore
        )
        .modelContainer(container)

        try await hostComposer(composer) { window, _ in
            try await openTheAddSheet(in: window)
            try await expectRankTile(in: window, from: "sharing a saved climb")
            try Self.photograph(window, named: "share-cluster-picker-3-saved-climb-rank")
        }
    }

    /// A workout whose snapshot this install has never read resolves it while the composer is
    /// already up, so the standing lands behind the presented screen.
    ///
    /// Hosted through a real `fullScreenCover` on purpose: the seed covers the frame-one case, and
    /// what is left to prove is that a standing landing in the presenter's own state reaches a
    /// composer the cover is already showing. A plain parent view would only prove the composer
    /// adopts a changed input, not that the cover delivers one.
    ///
    /// Both of the captain's symptoms are walked on the surfaces that show them: the Recaps tab
    /// gains its Standing card, and the Climb tab's grid gains the RANK cluster naming the frozen
    /// numbers. Against a composer that froze rank at init both stay missing for the whole
    /// presentation, which is the same rank-less card by a narrower route.
    @Test
    func aStandingThatLandsAfterTheComposerOpensStillReachesItsCards() async throws {
        let defaultsSuite = "ShareStatClusterPickerEvidenceTests-late-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let walkthroughStore = ShareComposerWalkthroughStore(defaults: defaults)
        walkthroughStore.markSeen()

        let container = try Self.makeContainer()
        let workout = ShareStatClusterPresetTests.recordedWorkout(
            name: "Empire State Building",
            trackingMode: .liveClimb,
            climbId: Climb.preview.id,
            heartRate: true,
            recordedSteps: 1_576
        )
        container.mainContext.insert(workout)
        try container.mainContext.save()

        let frozenStore = FrozenCompletionRankStore(defaults: defaults)
        let workoutId = UUID()
        let pending = LateArrivingStanding()
        let host = SharePresentingHost(
            workout: workout,
            walkthroughStore: walkthroughStore,
            pending: pending
        )
        .modelContainer(container)

        try await hostComposer(host) { window, _ in
            try await awaitControl(labelled: "Recaps", in: window)
            try activateAccessibilityElement(labelled: "Recaps", in: window)
            try await settle(window, seconds: 1.0)
            let beforeLabels = try await settledAccessibilityElements(under: window)
                .compactMap(\.accessibilityLabel)
            #expect(
                beforeLabels.allSatisfy { !$0.contains("Standing") },
                "a climb with no resolved standing was offered a Standing card. Saw: \(beforeLabels)"
            )

            pending.standing = await Self.fetchedStanding(workoutId: workoutId, in: frozenStore)
            try await settle(window, seconds: 1.2)

            let afterLabels = try await settledAccessibilityElements(under: window)
                .compactMap(\.accessibilityLabel)
            #expect(
                afterLabels.contains { $0.contains("Standing") },
                "the standing landed and the Recaps tab still had no Standing card. Saw: \(afterLabels)"
            )

            try await openTheAddSheet(in: window)
            try await expectRankTile(
                in: window,
                from: "a standing that landed after the composer opened"
            )
            try Self.photograph(window, named: "share-cluster-picker-4-late-standing-rank")
        }
    }

    /// A recap is a baked image, so the card a climber applies before the read finishes keeps
    /// whatever it was drawn with. When the standing lands the same template is redrawn and swapped
    /// in, or they export the empty rank tab the captain reported.
    ///
    /// Judged on the canvas region rather than in the accessibility tree, because a baked card
    /// publishes no text of its own, and an automatic redraw deliberately draws no overlay - so
    /// once the climber's own apply has settled, the swapped image is the only thing that can
    /// repaint there. The orderings that redraw has to survive are pinned without any timing in
    /// `ShareRecapBakeStateTests`, and that the swap keeps placed stickers is pinned on the view
    /// model, where routing it through a canvas reset would show up.
    @Test
    func aRecapAppliedBeforeTheStandingLandsIsRedrawnWithIt() async throws {
        let defaultsSuite = "ShareStatClusterPickerEvidenceTests-rebake-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let walkthroughStore = ShareComposerWalkthroughStore(defaults: defaults)
        walkthroughStore.markSeen()

        let container = try Self.makeContainer()
        let workout = ShareStatClusterPresetTests.recordedWorkout(
            name: "Empire State Building",
            trackingMode: .liveClimb,
            climbId: Climb.preview.id,
            heartRate: true,
            recordedSteps: 1_576
        )
        container.mainContext.insert(workout)
        try container.mainContext.save()

        let frozenStore = FrozenCompletionRankStore(defaults: defaults)
        let workoutId = UUID()
        let pending = LateArrivingStanding()
        let host = SharePresentingHost(
            workout: workout,
            walkthroughStore: walkthroughStore,
            pending: pending
        )
        .modelContainer(container)

        try await hostComposer(host) { window, _ in
            try await awaitControl(labelled: "Recaps", in: window)
            try activateAccessibilityElement(labelled: "Recaps", in: window)
            try await settle(window, seconds: 1.0)

            // The climber picks a card while the read is still out.
            try activateAccessibilityElement(in: window) {
                $0.accessibilityLabel?.hasSuffix("Result") == true
            }
            let rankless = try await settledCanvas(window)

            pending.standing = await Self.fetchedStanding(workoutId: workoutId, in: frozenStore)

            #expect(
                try await canvasChanges(from: rankless, in: window),
                "the applied recap kept the card it was baked with when the standing landed"
            )
            try Self.photograph(window, named: "share-cluster-picker-5-recap-rebaked-with-rank")
        }
    }

    // MARK: - Hosting

    /// Hosts the shipping composer in a phone-sized window and hands `body` the live window, then
    /// tears the window down however `body` ends.
    private func hostComposer<Root: View>(
        _ root: Root,
        _ body: (UIWindow, UIViewController) async throws -> Void
    ) async throws {
        try await withAccessibilityAutomation {
            let controller = UIHostingController(rootView: root)
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

            _ = try await settledAccessibilityElements(under: window)
            try await body(window, controller)
        }
    }

    /// The climber picks the climb's own artwork as a background; the add sheet then opens by
    /// itself, which is where the groups live. Searched from the window rather than the hosting
    /// controller's view so a composer presented in a cover is reachable too.
    private func openTheAddSheet(in window: UIWindow) async throws {
        try activateAccessibilityElement(labelled: "Presets", in: window)
        try await settle(window)
        try activateAccessibilityElement(in: window) {
            $0.accessibilityLabel == Climb.preview.name && $0.accessibilityTraits.contains(.button)
        }
        try await settle(window, seconds: 1.2)
    }

    /// Waits for a control the composer only publishes once its own `.task` has run.
    private func awaitControl(labelled label: String, in window: UIWindow) async throws {
        _ = try await settledAccessibilityElements(under: window) {
            $0.contains { $0.accessibilityLabel == label }
        }
    }

    // MARK: - Fixtures

    private static let leaderboardContext = LiveReplayLeaderboardContext.liveClimb(
        climbId: Climb.preview.id,
        targetSteps: 1_576
    )

    /// Staging's own `completionSnapshots` document for the climb the captain shared: 32nd of 85.
    private static func stagingSnapshot(workoutId: UUID) -> LiveReplayCompletionRankSnapshot {
        LiveReplayCompletionRankSnapshot(
            workoutId: workoutId.uuidString,
            rank: 32,
            completedCount: 85,
            completionDurationSeconds: 1_006,
            rankedAt: Date(timeIntervalSince1970: 1_787_859_963),
            rankingMetric: "completionDurationSeconds",
            tiePolicy: "competition_rank_equal_durations_share_rank"
        )
    }

    /// What the Share tap seeds from on a device that has already read this climb's standing: no
    /// request, no await, so the composer is built with the rank already in hand.
    private static func storedStanding(
        workoutId: UUID,
        in store: FrozenCompletionRankStore
    ) -> SavedClimbShareStanding? {
        store.freeze(stagingSnapshot(workoutId: workoutId), contextKey: leaderboardContext.contextKey)
        return SavedClimbShareStanding.stored(
            context: leaderboardContext,
            workoutId: workoutId.uuidString,
            service: CompletedClimbRankService(
                leaderboardService: StubLiveReplayLeaderboardService(),
                store: store
            )
        )
    }

    /// What the cover's own read produces for a workout this install has never held a snapshot for:
    /// the server document, fetched once and frozen, arriving after the composer is on screen.
    private static func fetchedStanding(
        workoutId: UUID,
        in store: FrozenCompletionRankStore
    ) async -> SavedClimbShareStanding? {
        let leaderboard = StubLiveReplayLeaderboardService()
        leaderboard.completionRankSnapshot = stagingSnapshot(workoutId: workoutId)
        return await SavedClimbShareStanding.resolve(
            context: leaderboardContext,
            workoutId: workoutId.uuidString,
            service: CompletedClimbRankService(leaderboardService: leaderboard, store: store)
        )
    }

    /// The tile reads out what it draws, so the frozen numbers have to be in it.
    private func expectRankTile(in window: UIWindow, from path: String) async throws {
        let sheetLabels = try await settledAccessibilityElements(under: window) {
            $0.contains { $0.accessibilityLabel?.hasSuffix("HERO") == true }
        }.compactMap(\.accessibilityLabel)
        let rankTile = sheetLabels.first { $0.hasSuffix("RANK") }
        #expect(
            rankTile != nil,
            "\(path) offered no RANK cluster. Saw: \(sheetLabels)"
        )
        #expect(
            rankTile?.contains("32") == true && rankTile?.contains("85") == true,
            "the RANK tile did not name the frozen standing. Saw: \(rankTile ?? "nothing")"
        )
    }

    private static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func settle(_ window: UIWindow, seconds: TimeInterval = 0.5) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            // Sleeping rather than spinning the run loop: the sheet's
            // presentation and the composer's own `Task.sleep` both need the
            // main actor free, not held by this loop.
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    /// The canvas region, as PNG bytes. Cropped above the action bar so the comparison answers a
    /// question about the card rather than about anything else on screen.
    private static func captureCanvas(_ window: UIWindow) throws -> Data {
        let canvas = CGRect(
            origin: .zero,
            size: CGSize(width: window.bounds.width, height: window.bounds.height * 0.6)
        )
        let image = UIGraphicsImageRenderer(size: canvas.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return try #require(image.pngData(), "UIImage produced no PNG data")
    }

    /// The canvas once it stops changing, so a render in flight is never mistaken for a finished
    /// card.
    private func settledCanvas(_ window: UIWindow, timeout: TimeInterval = 8) async throws -> Data {
        var last = try Self.captureCanvas(window)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await settle(window, seconds: 0.3)
            let next = try Self.captureCanvas(window)
            if next == last { return next }
            last = next
        }
        return last
    }

    /// Whether the canvas repaints away from `reference` before the deadline.
    private func canvasChanges(
        from reference: Data,
        in window: UIWindow,
        timeout: TimeInterval = 8
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await settle(window, seconds: 0.3)
            if try Self.captureCanvas(window) != reference { return true }
        }
        return false
    }

    /// What the window is drawing right now, as PNG bytes.
    private static func capture(_ window: UIWindow) throws -> Data {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return try #require(image.pngData(), "UIImage produced no PNG data")
    }

    private static func photograph(_ window: UIWindow, named name: String) throws {
        let png = try capture(window)

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)
        #expect(png.count > 5_000)
        print("evidence: \(url.path())")
    }
}

/// The standing Workout Detail is still reading when the composer opens.
@MainActor
@Observable
private final class LateArrivingStanding {
    var standing: SavedClimbShareStanding?
}

/// Stands in for the Share tap on Workout Detail, presentation included: the composer goes up in a
/// `fullScreenCover` before the frozen standing has been read, and the standing lands in the
/// presenter's state afterwards.
private struct SharePresentingHost: View {
    let workout: Workout
    let walkthroughStore: ShareComposerWalkthroughStore
    let pending: LateArrivingStanding
    @State private var isSharing = true

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .fullScreenCover(isPresented: $isSharing) {
                ShareComposerView(
                    workout: workout,
                    climb: .preview,
                    climbRank: pending.standing?.rank,
                    climbRankTotal: pending.standing?.totalClimbers,
                    walkthroughStore: walkthroughStore
                )
            }
    }
}
