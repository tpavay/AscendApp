import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence for the completed-climb summary's rank hero - the surface the three reported
/// defects were seen on (opening a saved Burj Khalifa summary from workout history).
///
/// Every image here is the real `LiveClimbCompletionSummaryView`, built the way its shipping call
/// sites build it, with the rank resolved through the real `CompletedClimbRankService` and the real
/// `FrozenCompletionRankStore`. Nothing is mocked into the view.
///
/// Each case hosts the summary in a live window, so the view's `.task` runs exactly as it does on
/// device. A zero settle captures the literal first frame - what a climber sees the instant the
/// summary opens - and a short settle captures where the surface lands.
///
/// Images land in `ASCEND_EVIDENCE_DIR` when it is set and in the test host's temporary directory
/// otherwise; the path is logged either way.
///
/// Serialized: every case drives the one real `UserDefaults`-backed store, so they cannot run
/// concurrently without clearing each other's records.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct CompletedClimbRankSummaryEvidenceTests {
    /// The reported workout: a Live Climb saved before `trackingMode` shipped, so its metadata
    /// decodes with a nil mode while still naming Burj Khalifa.
    private static let legacyBurjMetadataJSON = """
    {
      "source": "headphone_motion",
      "algorithmVersion": 1,
      "sampleRateAssumptionHz": 50,
      "sampleCount": 2400,
      "climbId": "burj-khalifa",
      "targetStepCount": 4554,
      "stopReason": "target_reached"
    }
    """

    private static let burjKhalifa = Climb(
        id: "burj-khalifa",
        name: "Burj Khalifa",
        city: "Dubai",
        country: "UAE",
        continent: "Asia",
        latitude: 25.1972,
        longitude: 55.2744,
        totalHeightMeters: 828,
        totalHeightFeet: 2_717,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 4_554,
        realStairCount: nil,
        calculatedFloors: 163,
        category: "skyscraper",
        tier: .gold,
        tags: ["tallest building"],
        funFact: "Burj Khalifa has 2,909 stairs from the ground floor to the 160th floor.",
        sourceURL: "https://en.wikipedia.org/wiki/Burj_Khalifa",
        imageSetVersion: 1,
        releaseState: .available
    )

    private static func legacyBurjWorkout() -> Workout {
        Workout(
            name: "Burj Khalifa Live Climb",
            date: Date(timeIntervalSince1970: 1_777_777_000),
            duration: 2_992,
            steps: 4_554,
            floors: 163,
            caloriesBurned: 612,
            source: .headphoneMotion,
            sourceMetadata: legacyBurjMetadataJSON
        )
    }

    /// The context the summary ranks against, derived exactly as `WorkoutDetailView` derives it.
    private static func summaryContext(for workout: Workout) -> LiveReplayLeaderboardContext? {
        LiveClimbWorkoutSummaryData.leaderboardContext(
            metadata: LiveClimbWorkoutSummaryData.metadata(for: workout),
            resolvedClimbId: burjKhalifa.id,
            climbTargetSteps: burjKhalifa.referenceStepCount,
            workoutSteps: workout.steps
        )
    }

    // MARK: - Defect 1 + 2: a completed climb's rank is frozen and reread from disk

    /// Opens the saved summary for the reported workout with the server's completion snapshot
    /// already frozen on this device. The hero must render the permanent standing - "21st of 64",
    /// labelled as the rank at completion - with no network read and no status word in the value
    /// slot.
    @Test
    func aFrozenCompletedRankRendersFromDiskAsThePermanentStanding() async throws {
        let store = FrozenCompletionRankStore()
        defer { store.removeAll() }
        store.removeAll()

        let workout = Self.legacyBurjWorkout()
        let context = try #require(
            Self.summaryContext(for: workout),
            "A Live Climb saved before trackingMode existed must still rank on its climb board"
        )

        store.freeze(
            LiveReplayCompletionRankSnapshot(
                workoutId: workout.id.uuidString,
                rank: 21,
                completedCount: 64,
                completionDurationSeconds: workout.duration,
                rankedAt: Date(timeIntervalSince1970: 1_777_777_600),
                rankingMetric: "completionDurationSeconds",
                tiePolicy: "competition_rank_equal_durations_share_rank"
            ),
            contextKey: context.contextKey
        )

        let image = try await hostAndCapture(
            try summary(workout: workout, climb: Self.burjKhalifa, context: context),
            settleSeconds: 0.5
        )
        let text = try await recognizedText(in: image)

        // The permanent standing, position and denominator together.
        #expect(text.contains("21st"))
        #expect(text.contains("of 64"))
        #expect(text.contains("climb rank"))
        #expect(text.contains("rank when you finished"))

        // A frozen standing never claims to be today's standing...
        #expect(!text.contains("current leaderboard rank"))
        // ...and no status word stands where the rank belongs.
        #expect(!text.contains("checking"))
        #expect(!text.contains("unavailable"))
        #expect(!text.contains("looking for your rank"))

        try writeEvidence(image: image, named: "completed-summary-frozen-rank.png")
    }

    /// The same workout reopened after the record is on disk: the second render is identical, which
    /// is the user-visible half of "stored once and reused" - no re-fetch, no second answer.
    @Test
    func reopeningTheSameSummaryShowsTheSameFrozenNumbers() async throws {
        let store = FrozenCompletionRankStore()
        defer { store.removeAll() }
        store.removeAll()

        let workout = Self.legacyBurjWorkout()
        let context = try #require(Self.summaryContext(for: workout))
        store.freeze(
            LiveReplayCompletionRankSnapshot(
                workoutId: workout.id.uuidString,
                rank: 21,
                completedCount: 64,
                completionDurationSeconds: workout.duration,
                rankedAt: Date(timeIntervalSince1970: 1_777_777_600),
                rankingMetric: "completionDurationSeconds",
                tiePolicy: "competition_rank_equal_durations_share_rank"
            ),
            contextKey: context.contextKey
        )

        // A later disagreeing server read is a recomputation, not a correction.
        store.freeze(
            LiveReplayCompletionRankSnapshot(
                workoutId: workout.id.uuidString,
                rank: 34,
                completedCount: 91,
                completionDurationSeconds: workout.duration,
                rankedAt: Date(timeIntervalSince1970: 1_777_999_600),
                rankingMetric: "completionDurationSeconds",
                tiePolicy: "competition_rank_equal_durations_share_rank"
            ),
            contextKey: context.contextKey
        )

        let image = try await hostAndCapture(
            try summary(workout: workout, climb: Self.burjKhalifa, context: context),
            settleSeconds: 0.5
        )
        let text = try await recognizedText(in: image)

        #expect(text.contains("21st"))
        #expect(text.contains("of 64"))
        #expect(!text.contains("34th"))
        #expect(!text.contains("of 91"))

        try writeEvidence(image: image, named: "completed-summary-frozen-rank-reopened.png")
    }

    // MARK: - Defect 3: the value loads, it is never worded

    /// The first frame of the same summary with nothing frozen yet: the label stays put and only
    /// the value slot carries the shared skeleton treatment. This is the frame that used to read
    /// "Complete" / "Checking".
    @Test
    func theFirstFrameSkeletonsTheValueInsteadOfWordingIt() async throws {
        let store = FrozenCompletionRankStore()
        defer { store.removeAll() }
        store.removeAll()

        let workout = Self.legacyBurjWorkout()
        let context = try #require(Self.summaryContext(for: workout))

        let image = try await hostAndCapture(
            try summary(workout: workout, climb: Self.burjKhalifa, context: context),
            settleSeconds: 0
        )
        let text = try await recognizedText(in: image)

        // Label visible, value loading: the detail line reads straight after the label because
        // nothing but the skeleton occupies the value slot between them.
        #expect(text.contains("climb rank looking for your rank"))

        // No status word standing in for the rank.
        #expect(!text.contains("checking"))
        #expect(!text.contains("unavailable"))
        #expect(!text.contains("21st"))

        // The achievement row below still states the session finished.
        #expect(text.contains("climb complete"))

        try writeEvidence(image: image, named: "completed-summary-rank-loading.png")
    }

    // MARK: - A session that ranks nowhere renders no ranking card at all

    /// A routine session with no leaderboard behind it. The ranking card is absent entirely rather
    /// than showing "Complete" where a rank goes; the achievement row below still states that the
    /// session finished.
    @Test
    func aSessionThatRanksNowhereRendersNoRankingCard() async throws {
        let workout = Workout(
            name: "Pyramid Intervals",
            date: Date(timeIntervalSince1970: 1_777_777_000),
            duration: 1_800,
            steps: 2_412,
            floors: 86,
            caloriesBurned: 344,
            source: .headphoneMotion
        )

        let presentation = RoutineCompletionSummaryPresentation(
            stopReason: .targetReached,
            hasRoutineLeaderboard: false
        )
        #expect(presentation.ranksOnLeaderboard == false)

        let image = try await hostAndCapture(
            LiveClimbCompletionSummaryView(
                climb: nil,
                workout: workout,
                leaderboardRank: nil,
                leaderboardTotal: nil,
                leaderboardRankBasis: .current,
                allowsRatingPrompt: false,
                leaderboardContext: nil,
                rankingLabelOverride: "ROUTINE RANK",
                ranksOnLeaderboard: presentation.ranksOnLeaderboard,
                achievementTitleOverride: presentation.achievementTitleOverride,
                achievementIconNameOverride: presentation.achievementIconNameOverride,
                onDone: {}
            )
            .modelContainer(for: Self.summaryModels, inMemory: true),
            settleSeconds: 0.4
        )
        let text = try await recognizedText(in: image)

        // No rank hero: no label, no value slot, no detail line.
        #expect(!text.contains("routine rank"))
        #expect(!text.contains("climb rank"))
        #expect(!text.contains("global rank"))
        #expect(!text.contains("looking for your rank"))
        #expect(!text.contains("incomplete"))

        try writeEvidence(image: image, named: "completed-summary-no-ranking-card.png")
    }

    // MARK: - The one state that is still allowed to say "current"

    /// A standing recomputed against today's rows, which is deliberately *not* frozen and says so.
    /// This is the contrast that makes the label change legible: the same hero, the other wording.
    @Test
    func aRecomputedStandingKeepsSayingItIsTodaysStanding() async throws {
        let workout = Workout(
            name: "Open Climb",
            date: Date(timeIntervalSince1970: 1_777_777_000),
            duration: 1_620,
            steps: 2_096,
            floors: 74,
            caloriesBurned: 298,
            source: .headphoneMotion
        )

        let image = try await hostAndCapture(
            LiveClimbCompletionSummaryView(
                climb: nil,
                workout: workout,
                leaderboardRank: 12,
                leaderboardTotal: 2_460,
                // A rank this surface recomputed against today's rows - the one basis that is
                // still allowed to say "current".
                leaderboardRankBasis: .current,
                allowsRatingPrompt: false,
                leaderboardContext: .justClimbGlobal(targetSteps: 2_096),
                onDone: {}
            )
            .modelContainer(for: Self.summaryModels, inMemory: true),
            settleSeconds: 0.4
        )
        let text = try await recognizedText(in: image)

        #expect(text.contains("12th"))
        #expect(text.contains("2,460"))
        #expect(text.contains("global rank"))
        #expect(text.contains("current leaderboard rank"))
        #expect(!text.contains("rank when you finished"))

        try writeEvidence(image: image, named: "open-session-current-rank.png")
    }

    // MARK: - Building the surface

    private func summary(
        workout: Workout,
        climb: Climb,
        context: LiveReplayLeaderboardContext
    ) throws -> some View {
        // The argument list `WorkoutDetailView` passes when a saved Live Climb summary is opened.
        LiveClimbCompletionSummaryView(
            climb: climb,
            workout: workout,
            leaderboardRank: nil,
            leaderboardTotal: nil,
            leaderboardRankBasis: .current,
            allowsRatingPrompt: false,
            leaderboardContext: context,
            rankingLabelOverride: nil,
            ranksOnLeaderboard: true,
            onDone: {}
        )
        .modelContainer(try summaryContainer())
    }

    private static let summaryModels: [any PersistentModel.Type] = [
        Workout.self,
        ClimbAttempt.self,
        BestEffortCacheEntry.self,
        BestEffortCacheMetadata.self
    ]

    /// Held for the process, not built per render.
    ///
    /// `LiveClimbCompletionSummaryView` carries a `@Query`, and SwiftUI keeps observing SwiftData
    /// for a beat after the host is torn down. A per-render container is gone before that observer
    /// is, and the observer then traps on the dangling reference the next time *any* suite calls
    /// `ModelContext.save()` - taking the whole test process down with it, attributed to whatever
    /// unrelated code happened to be saving. `.modelContainer(for:inMemory:)` is what makes it
    /// per-render, so this suite may not use it.
    private static let container: ModelContainer? = try? ModelContainer(
        for: Schema(summaryModels),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    private func summaryContainer() throws -> ModelContainer {
        try #require(Self.container, "The evidence suite needs an in-memory model container")
    }

    // MARK: - Capture

    /// Hosts the view in a real window so `.task` runs, then captures what is on screen.
    ///
    /// The window is dismantled and detached from the scene before this returns. Hiding it is not
    /// enough: a window still attached to the shared scene keeps its SwiftUI content - and the
    /// SwiftData observers behind the summary's `@Query` - alive for the rest of the test run, and
    /// the next capture's key-window switch then drives appearance transitions back through those
    /// stale hosting controllers while unrelated suites are mutating their own model containers.
    private func hostAndCapture(_ view: some View, settleSeconds: Double) async throws -> UIImage {
        let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "The test host app must have a window scene to render into"
        )
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = bounds

        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
            window.rootViewController = nil
            window.windowScene = nil
        }

        let host = AppearanceTrackingHostingController(
            rootView: AnyView(view.environment(\.colorScheme, .dark))
        )
        host.view.frame = bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // UIKit ends the appearance transition it began when the window became visible on a later
        // run-loop turn, so a zero settle would otherwise capture and dismantle the host while that
        // transition is still open. Waiting on the callback rather than on a guessed interval keeps
        // this deterministic on a loaded runner.
        try await waitUntilAppeared(host)

        // Awaiting is what lets the view's `.task` start, so a zero settle captures the literal
        // first frame - what a climber sees the instant the summary opens.
        if settleSeconds > 0 {
            try await Task.sleep(for: .seconds(settleSeconds))
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    /// Waits for UIKit to finish the appearance transition, with a deadline generous enough that a
    /// busy runner cannot be mistaken for a broken one.
    ///
    /// Five seconds was not: a full parallel run on a contended machine took this suite past it once
    /// in six, and the resulting red says "the summary never appeared" about a machine that was
    /// merely slow. The deadline exists to stop a genuinely stuck transition from hanging the run,
    /// so it only has to be shorter than a person's patience - it buys nothing by being tight, and
    /// a passing run still leaves it the instant `viewDidAppear` lands.
    private func waitUntilAppeared(_ host: AppearanceTrackingHostingController) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        while host.hasAppeared == false, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(host.hasAppeared, "The hosted summary never finished its appearance transition")
    }

    // MARK: - Reading the rendered pixels back

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
    }

    private func writeEvidence(image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: name)
        try png.write(to: url)
        #expect(png.count > 5_000)

        // Logged so the image is findable inside the simulator container when no
        // ASCEND_EVIDENCE_DIR was provided.
        print("Rendered completed-climb rank evidence: \(url.path())")
    }
}

/// Reports when UIKit has finished bringing the hosted summary on screen, so a capture never runs -
/// and the host is never torn down - in the middle of the window's appearance transition.
@MainActor
private final class AppearanceTrackingHostingController: UIHostingController<AnyView> {
    private(set) var hasAppeared = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
}
