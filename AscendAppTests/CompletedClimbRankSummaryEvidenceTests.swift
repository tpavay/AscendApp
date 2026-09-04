import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence for the completed-climb summary's rank hero - the surface the three reported defects
/// were seen on (opening a saved Burj Khalifa summary from workout history).
///
/// Every case hosts the real `LiveClimbCompletionSummaryView`, built the way its shipping call
/// sites build it, with the rank resolved through the real `CompletedClimbRankService` and the real
/// `FrozenCompletionRankStore`. Nothing is mocked into the view.
///
/// Each case hosts the summary in a live window through `RenderedScreen`, so the view's `.task`
/// runs exactly as it does on device, and reads the copy back off the accessibility tree. A zero
/// settle reads the literal first frame - what a climber sees the instant the summary opens - and a
/// short settle reads where the surface lands.
///
/// Photographs are written to `ASCEND_EVIDENCE_DIR` when it is set and not taken otherwise.
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
        realStairCount: 2_909,
        calculatedFloors: 160,
        category: "skyscraper",
        tier: .diamond,
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

        let text = try await hostedCopy(
            try summary(workout: workout, climb: Self.burjKhalifa, context: context),
            settleSeconds: 0.5,
            photographedAs: "completed-summary-frozen-rank"
        ) { $0.contains("21st") }

        // The permanent standing, position, field size, and ranking basis together.
        #expect(text.contains("21st"))
        #expect(text.contains("fastest of 64"))
        #expect(text.contains("burj khalifa"))
        #expect(!text.contains("climb rank"))
        #expect(!text.contains("rank when you finished"))

        // A frozen standing never claims to be today's standing...
        #expect(!text.contains("current leaderboard rank"))
        // ...and no status word stands where the rank belongs.
        #expect(!text.contains("checking"))
        #expect(!text.contains("unavailable"))
        #expect(!text.contains("looking for your rank"))
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

        let text = try await hostedCopy(
            try summary(workout: workout, climb: Self.burjKhalifa, context: context),
            settleSeconds: 0.5,
            photographedAs: "completed-summary-frozen-rank-reopened"
        ) { $0.contains("21st") }

        #expect(text.contains("21st"))
        #expect(text.contains("fastest of 64"))
        #expect(!text.contains("34th"))
        #expect(!text.contains("fastest of 91"))
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

        let text = try await hostedCopy(
            try summary(workout: workout, climb: Self.burjKhalifa, context: context),
            settleSeconds: 0,
            photographedAs: "completed-summary-rank-loading"
        ) { $0.contains("looking for your rank") }

        #expect(text.contains("looking for your rank"))
        #expect(!text.contains("climb rank"))

        // No status word standing in for the rank.
        #expect(!text.contains("checking"))
        #expect(!text.contains("unavailable"))
        #expect(!text.contains("21st"))

        // The achievement row below still states the session finished.
        #expect(text.contains("climb complete"))
    }

    // MARK: - A session that ranks nowhere renders no rank hero at all

    /// A routine session with no leaderboard behind it. The rank hero is absent entirely rather
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

        let text = try await hostedCopy(
            LiveClimbCompletionSummaryView(
                climb: nil,
                workout: workout,
                leaderboardRank: nil,
                leaderboardTotal: nil,
                leaderboardRankBasis: .current,
                leaderboardContext: nil,
                rankingLabelOverride: "ROUTINE RANK",
                ranksOnLeaderboard: presentation.ranksOnLeaderboard,
                achievementTitleOverride: presentation.achievementTitleOverride,
                achievementIconNameOverride: presentation.achievementIconNameOverride,
                onDone: { _ in }
            )
            .modelContainer(for: Self.summaryModels, inMemory: true),
            settleSeconds: 0.4,
            photographedAs: "completed-summary-no-ranking-card"
        )

        // No rank hero: no label, no value slot, no detail line.
        #expect(!text.contains("routine rank"))
        #expect(!text.contains("climb rank"))
        #expect(!text.contains("global rank"))
        #expect(!text.contains("looking for your rank"))
        #expect(!text.contains("incomplete"))
    }

    // MARK: - A rank recomputed against the current field

    /// A standing recomputed against today's rows uses the same concise field-size treatment.
    @Test
    func aRecomputedStandingUsesThePlainLanguageFieldLine() async throws {
        let workout = Workout(
            name: "Open Climb",
            date: Date(timeIntervalSince1970: 1_777_777_000),
            duration: 1_620,
            steps: 2_096,
            floors: 74,
            caloriesBurned: 298,
            source: .headphoneMotion
        )

        let text = try await hostedCopy(
            LiveClimbCompletionSummaryView(
                climb: nil,
                workout: workout,
                leaderboardRank: 12,
                leaderboardTotal: 2_460,
                // A rank this surface recomputed against today's rows - the one basis that is
                // still allowed to say "current".
                leaderboardRankBasis: .current,
                leaderboardContext: .justClimbGlobal(targetSteps: 2_096),
                onDone: { _ in }
            )
            .modelContainer(for: Self.summaryModels, inMemory: true),
            settleSeconds: 0.4,
            photographedAs: "open-session-current-rank"
        ) { $0.contains("12th") }

        #expect(text.contains("12th"))
        #expect(text.contains("fastest of 2,460"))
        #expect(!text.contains("global rank"))
        #expect(!text.contains("current leaderboard rank"))
        #expect(!text.contains("rank when you finished"))
    }

    // MARK: - The population a frozen standing was measured against

    /// The two standings a server can freeze for one attempt on a board of three
    /// climbers where a single rival holds five faster attempts.
    ///
    /// A rank counted off entry rows read that rival as five opponents and placed
    /// the climber 6th, while the field size beside it counted three climbers; a
    /// clamp then rewrote 6th down to 3. The climber who finished 2nd read last
    /// place, permanently, because the snapshot behind this surface is write-once.
    /// Counting one population on both halves renders the position the field
    /// actually placed.
    @Test
    func aFrozenStandingReadsAsThePositionTheFieldPlaced() async throws {
        let clamped = try await frozenStanding(
            rank: 3,
            completedCount: 3,
            named: "frozen-standing-clamped-3rd-of-3"
        )

        #expect(clamped.contains("3rd"))
        #expect(clamped.contains("fastest of 3"))

        let counted = try await frozenStanding(
            rank: 2,
            completedCount: 3,
            named: "frozen-standing-counted-2nd-of-3"
        )

        #expect(counted.contains("2nd"))
        #expect(counted.contains("fastest of 3"))
    }

    /// Freezes one server-published standing on this device and hosts the saved
    /// summary that reads it back, returning the copy read off the tree.
    private func frozenStanding(
        rank: Int,
        completedCount: Int,
        named name: String
    ) async throws -> String {
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
                rank: rank,
                completedCount: completedCount,
                completionDurationSeconds: workout.duration,
                rankedAt: Date(timeIntervalSince1970: 1_777_777_600),
                rankingMetric: "completionDurationSeconds",
                tiePolicy: "competition_rank_equal_durations_share_rank"
            ),
            contextKey: context.contextKey
        )

        return try await hostedCopy(
            try summary(workout: workout, climb: Self.burjKhalifa, context: context),
            settleSeconds: 0.5,
            photographedAs: name
        ) { $0.contains(rank.rankOrdinalText.lowercased()) }
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
            leaderboardContext: context,
            rankingLabelOverride: nil,
            ranksOnLeaderboard: true,
            onDone: { _ in }
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

    // MARK: - Reading the hosted screen back

    /// Hosts the view in a real window so `.task` runs, then reads its copy off the accessibility
    /// tree - waiting for `isReady` so the read is the frame the case is about - and photographs
    /// it when `ASCEND_EVIDENCE_DIR` is set.
    ///
    /// `RenderedScreen` dismantles the window and detaches it from the scene before this returns.
    /// Hiding it would not be enough: a window still attached to the shared scene keeps its
    /// SwiftUI content - and the SwiftData observers behind the summary's `@Query` - alive for the
    /// rest of the test run, and the next host's key-window switch then drives appearance
    /// transitions back through those stale hosting controllers while unrelated suites are
    /// mutating their own model containers.
    private func hostedCopy(
        _ view: some View,
        settleSeconds: Double,
        photographedAs name: String,
        until isReady: @escaping (String) -> Bool = { $0.isEmpty == false }
    ) async throws -> String {
        let host = AppearanceTrackingHostingController(
            rootView: AnyView(view.environment(\.colorScheme, .dark))
        )

        // UIKit ends the appearance transition it began when the window became visible on a later
        // run-loop turn, so a zero settle would otherwise read and dismantle the host while that
        // transition is still open. Waiting on the callback rather than on a guessed interval keeps
        // this deterministic on a loaded runner.
        //
        // The deadline is generous on purpose. Five seconds was not: a full parallel run on a
        // contended machine took this suite past it once in six, and the resulting red says "the
        // summary never appeared" about a machine that was merely slow. It exists to stop a
        // genuinely stuck transition from hanging the run, so it only has to be shorter than a
        // person's patience, and a passing run still leaves it the instant `viewDidAppear` lands.
        return try await RenderedScreen.host(
            host,
            settle: .until(turns: 12_000, interval: .milliseconds(5)) { _ in host.hasAppeared }
        ) { screen in
            #expect(host.hasAppeared, "The hosted summary never finished its appearance transition")

            // Awaiting is what lets the view's `.task` start, so a zero settle reads the literal
            // first frame - what a climber sees the instant the summary opens.
            if settleSeconds > 0 {
                try await Task.sleep(for: .seconds(settleSeconds))
            }

            let text = try await screen.copy(until: isReady)
            try screen.photograph(named: name)
            return text
        }
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
