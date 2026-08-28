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

        try await hostComposer(composer) { window, controller in
            try await openTheAddSheet(in: controller, window: window)

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
    /// What runs here is the saved path's data - the frozen `completionSnapshots` document staging
    /// holds for that climb, through `SavedClimbShareStanding` and `CompletedClimbRankService` -
    /// handed to the shipping composer, and the assertion is the tile list he enumerated. It does
    /// not exercise `WorkoutDetailView` itself; what stops a new entry point from silently
    /// dropping rank again is that `ShareComposerView`'s rank parameters carry no defaults, so
    /// omitting them is a compile error.
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
        let standing = await Self.frozenStanding(workoutId: workoutId, in: frozenStore)

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

        try await hostComposer(composer) { window, controller in
            try await openTheAddSheet(in: controller, window: window)
            try await expectRankTile(in: window, from: "sharing a saved climb")
            try Self.photograph(window, named: "share-cluster-picker-3-saved-climb-rank")
        }
    }

    /// A saved climb's standing is read when the composer opens, so it lands after the first frame.
    /// The composer has to adopt it instead of freezing the nothing it held at init.
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
        let host = LateArrivingStandingHost(
            workout: workout,
            walkthroughStore: walkthroughStore,
            pending: pending
        )
        .modelContainer(container)

        try await hostComposer(host) { window, controller in
            _ = try await settledAccessibilityElements(under: controller.view) {
                $0.contains { $0.accessibilityLabel == "Recaps" }
            }
            try activateAccessibilityElement(labelled: "Recaps", in: controller.view)
            try await settle(window, seconds: 1.0)
            let beforeLabels = try await settledAccessibilityElements(under: window)
                .compactMap(\.accessibilityLabel)
            #expect(
                beforeLabels.allSatisfy { !$0.contains("Standing") },
                "a climb with no resolved standing was offered a Standing card. Saw: \(beforeLabels)"
            )

            pending.standing = await Self.frozenStanding(workoutId: workoutId, in: frozenStore)
            try await settle(window, seconds: 1.2)

            let afterLabels = try await settledAccessibilityElements(under: window)
                .compactMap(\.accessibilityLabel)
            #expect(
                afterLabels.contains { $0.contains("Standing") },
                "the standing landed and the Recaps tab still had no Standing card. Saw: \(afterLabels)"
            )

            try await openTheAddSheet(in: controller, window: window)
            try await expectRankTile(
                in: window,
                from: "a standing that landed after the composer opened"
            )
            try Self.photograph(window, named: "share-cluster-picker-4-late-standing-rank")
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

            _ = try await settledAccessibilityElements(under: controller.view)
            try await body(window, controller)
        }
    }

    /// The climber picks the climb's own artwork as a background; the add sheet then opens by
    /// itself, which is where the groups live.
    private func openTheAddSheet(in controller: UIViewController, window: UIWindow) async throws {
        try activateAccessibilityElement(labelled: "Presets", in: controller.view)
        try await settle(window)
        try activateAccessibilityElement(in: controller.view) {
            $0.accessibilityLabel == Climb.preview.name && $0.accessibilityTraits.contains(.button)
        }
        try await settle(window, seconds: 1.2)
    }

    // MARK: - Fixtures

    /// Staging's own `completionSnapshots` document for the climb the captain shared: 32nd of 85,
    /// resolved through the one read path a saved climb uses.
    private static func frozenStanding(
        workoutId: UUID,
        in store: FrozenCompletionRankStore
    ) async -> SavedClimbShareStanding? {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: Climb.preview.id,
            targetSteps: 1_576
        )
        store.freeze(
            LiveReplayCompletionRankSnapshot(
                workoutId: workoutId.uuidString,
                rank: 32,
                completedCount: 85,
                completionDurationSeconds: 1_006,
                rankedAt: Date(timeIntervalSince1970: 1_787_859_963),
                rankingMetric: "completionDurationSeconds",
                tiePolicy: "competition_rank_equal_durations_share_rank"
            ),
            contextKey: context.contextKey
        )

        return await SavedClimbShareStanding.resolve(
            context: context,
            workoutId: workoutId.uuidString,
            service: CompletedClimbRankService(
                leaderboardService: StubLiveReplayLeaderboardService(),
                store: store
            )
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

/// The standing Workout Detail is still reading when the composer opens.
@MainActor
@Observable
private final class LateArrivingStanding {
    var standing: SavedClimbShareStanding?
}

/// Stands in for the Share tap on Workout Detail: the composer is presented before the frozen
/// standing has been read, and is handed it when it lands.
private struct LateArrivingStandingHost: View {
    let workout: Workout
    let walkthroughStore: ShareComposerWalkthroughStore
    let pending: LateArrivingStanding

    var body: some View {
        ShareComposerView(
            workout: workout,
            climb: .preview,
            climbRank: pending.standing?.rank,
            climbRankTotal: pending.standing?.totalClimbers,
            walkthroughStore: walkthroughStore
        )
    }
}
