import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// End-to-end visual evidence for the ranking-and-ghost finish card: the whole
/// `LiveClimbCompletionSummaryView` a climber actually opens, not the hero
/// component on its own.
///
/// Nothing is injected past the view's own boundary. The climber's five
/// completions of the tower are real `ClimbAttempt` rows in a real (in-memory)
/// store, the placing is resolved by the shipping `ClimbService` from the view's
/// own `.task`, and the standing is read back through the real
/// `FrozenCompletionRankStore`. The two cases differ only in the field size the
/// server froze, which is exactly what the governing rule turns on.
///
/// PNGs land in `ASCEND_EVIDENCE_DIR` when set, the test host's temp dir
/// otherwise; the path is logged either way.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct RankingGhostFinishCardJourneyEvidenceTests {
    /// The climber's own history on the tower: four earlier finishes, one of them
    /// faster than the run being placed and three slower, so today's repeat is
    /// their 2nd of 5.
    private static let earlierCompletionDurations = [2_400, 3_080, 3_100, 3_500]
    /// Today's run. Not the climber's fastest - the case that used to
    /// congratulate them with `1st of 1 CLIMBER` regardless.
    private static let placedDurationSeconds = 2_992

    private static let stPeters = Climb(
        id: "st-peters-basilica",
        name: "St. Peter's Basilica",
        city: "Vatican City",
        country: "Vatican City",
        continent: "Europe",
        latitude: 41.9022,
        longitude: 12.4539,
        totalHeightMeters: 136,
        totalHeightFeet: 448,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 748,
        realStairCount: 551,
        calculatedFloors: 28,
        category: "landmark",
        tier: .silver,
        tags: ["dome"],
        funFact: "551 steps run from the floor of the basilica to the top of the dome.",
        sourceURL: "https://en.wikipedia.org/wiki/St._Peter%27s_Basilica",
        imageSetVersion: 1,
        releaseState: .available
    )

    // MARK: - The solo repeat

    /// Alone on the tower, on a repeat that was slower than two of the climber's
    /// own earlier runs.
    ///
    /// The server froze a standing of 1st over a field of one, and the hero
    /// refuses it: `1st of 1 CLIMBER` was invariant across every possible
    /// performance. What renders instead is the placing among the climber's own
    /// climbs, which can fall - and here it has.
    @Test
    func aSoloSlowerRepeatOpensOnItsPlacingAmongTheClimbersOwnClimbs() async throws {
        let text = try await finishCard(
            frozenRank: 1,
            frozenFieldSize: 1,
            named: "finish-card-journey-solo-slower-repeat.png"
        )

        // The hero: the ordinal, over the climber's own field.
        #expect(text.contains("2nd"))
        #expect(text.contains("of your 5 climbs"))

        // No leaderboard rank, in any of its wordings, over a field of one.
        #expect(!text.contains("1 climber"))
        #expect(!text.contains("of 1 climber"))
        #expect(!text.contains("rank you just earned"))
        #expect(!text.contains("rank when you finished"))
        #expect(!text.contains("current leaderboard rank"))

        // The placing did not also drop to the achievement row: it *is* the hero.
        #expect(text.contains("climb complete"))
    }

    // MARK: - The repeat with a rival on the board

    /// The identical climber, the identical history, one rival on the tower.
    ///
    /// The leaderboard rank takes the hero and the personal placing drops to the
    /// achievement row - two ordinals, each naming the field it counts.
    @Test
    func aRivalOnTheTowerTakesTheHeroAndDropsThePlacingToTheAchievementRow() async throws {
        let text = try await finishCard(
            frozenRank: 2,
            frozenFieldSize: 4,
            named: "finish-card-journey-rival-repeat.png"
        )

        // The hero is the leaderboard standing over the real field.
        #expect(text.contains("2nd"))
        #expect(text.contains("of 4 climbers"))

        // The personal placing is still stated - in the achievement row.
        #expect(text.contains("of your 5 climbs"))
        #expect(!text.contains("climb complete"))
    }

    // MARK: - Building the surface

    /// Seeds the climber's five completions of the tower, freezes one server
    /// standing for the run being placed, renders the shipping summary, and
    /// returns the copy read back off the pixels.
    private func finishCard(
        frozenRank: Int,
        frozenFieldSize: Int,
        named name: String
    ) async throws -> String {
        let store = FrozenCompletionRankStore()
        defer { store.removeAll() }
        store.removeAll()

        let container = try #require(Self.container, "The evidence suite needs a model container")
        let context = ModelContext(container)
        try context.delete(model: ClimbAttempt.self)
        try context.save()

        let completedAt = Date(timeIntervalSince1970: 1_777_777_000)
        let workout = Workout(
            name: "St. Peter's Basilica Live Climb",
            date: completedAt.addingTimeInterval(-Double(Self.placedDurationSeconds)),
            duration: TimeInterval(Self.placedDurationSeconds),
            steps: 551,
            floors: 28,
            caloriesBurned: 188,
            source: .headphoneMotion,
            sourceMetadata: Self.metadataJSON
        )

        // Four earlier finishes, each its own row naming its own workout, so the
        // history is complete evidence rather than a collapsed stand-in.
        for (offset, duration) in Self.earlierCompletionDurations.enumerated() {
            let earlier = completedAt.addingTimeInterval(-Double(86_400 * (offset + 1)))
            context.insert(ClimbAttempt(
                climbId: Self.stPeters.id,
                status: .completed,
                startedAt: earlier.addingTimeInterval(-Double(duration)),
                endedAt: earlier,
                completedAt: earlier,
                accumulatedSteps: 551,
                accumulatedDurationSeconds: duration,
                sessionsCount: 1,
                appliedWorkoutIds: [UUID().uuidString],
                bestCompletionDurationSeconds: duration,
                // Non-nil and not 1: this climber did not take the First Ascent,
                // and a known order keeps the summary off the network.
                globalCompletionOrder: 12
            ))
        }

        // The run being placed, as its own row.
        context.insert(ClimbAttempt(
            climbId: Self.stPeters.id,
            status: .completed,
            startedAt: workout.date,
            endedAt: completedAt,
            completedAt: completedAt,
            accumulatedSteps: 551,
            accumulatedDurationSeconds: Self.placedDurationSeconds,
            sessionsCount: 1,
            appliedWorkoutIds: [workout.id.uuidString],
            bestCompletionDurationSeconds: Self.placedDurationSeconds,
            globalCompletionOrder: 12
        ))
        try context.save()

        let leaderboardContext = try #require(
            LiveClimbWorkoutSummaryData.leaderboardContext(
                metadata: LiveClimbWorkoutSummaryData.metadata(for: workout),
                resolvedClimbId: Self.stPeters.id,
                climbTargetSteps: Self.stPeters.referenceStepCount,
                workoutSteps: workout.steps
            ),
            "A Live Climb on a catalog tower must rank on that tower's board"
        )

        store.freeze(
            LiveReplayCompletionRankSnapshot(
                workoutId: workout.id.uuidString,
                rank: frozenRank,
                completedCount: frozenFieldSize,
                completionDurationSeconds: workout.duration,
                rankedAt: completedAt,
                rankingMetric: "completionDurationSeconds",
                tiePolicy: "competition_rank_equal_durations_share_rank"
            ),
            contextKey: leaderboardContext.contextKey
        )

        let image = try await hostAndCapture(
            LiveClimbCompletionSummaryView(
                climb: Self.stPeters,
                workout: workout,
                leaderboardRank: nil,
                leaderboardTotal: nil,
                leaderboardRankBasis: .current,
                leaderboardContext: leaderboardContext,
                moment: .freshCompletion,
                onDone: { _ in }
            )
            .modelContainer(container),
            settleSeconds: 0.6
        )

        try writeEvidence(image: image, named: name)
        return try await recognizedText(in: image)
    }

    private static let metadataJSON = """
    {
      "source": "headphone_motion",
      "algorithmVersion": 1,
      "sampleRateAssumptionHz": 50,
      "sampleCount": 2400,
      "climbId": "st-peters-basilica",
      "targetStepCount": 551,
      "stopReason": "target_reached"
    }
    """

    private static let summaryModels: [any PersistentModel.Type] = [
        Workout.self,
        ClimbAttempt.self,
        BestEffortCacheEntry.self,
        BestEffortCacheMetadata.self
    ]

    /// Held for the process, not built per render: the summary carries a `@Query`
    /// whose SwiftData observer outlives the host, and a per-render container is
    /// gone before it is. Same reasoning as
    /// `CompletedClimbRankSummaryEvidenceTests`.
    private static let container: ModelContainer? = try? ModelContainer(
        for: Schema(summaryModels),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    // MARK: - Capture

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

        let host = JourneyAppearanceTrackingHostingController(
            rootView: AnyView(view.environment(\.colorScheme, .dark))
        )
        host.view.frame = bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        try await waitUntilAppeared(host)

        if settleSeconds > 0 {
            try await Task.sleep(for: .seconds(settleSeconds))
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    private func waitUntilAppeared(_ host: JourneyAppearanceTrackingHostingController) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        while host.hasAppeared == false, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(host.hasAppeared, "The hosted summary never finished its appearance transition")
    }

    // MARK: - Reading the rendered pixels back

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

        return (request.results ?? [])
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
        print("Rendered ranking-ghost evidence: \(url.path())")
    }
}

/// Mirrors the appearance-tracking host the other summary evidence suite uses;
/// that one is file-private, and a second copy is cheaper than widening it.
private final class JourneyAppearanceTrackingHostingController: UIHostingController<AnyView> {
    private(set) var hasAppeared = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
}
