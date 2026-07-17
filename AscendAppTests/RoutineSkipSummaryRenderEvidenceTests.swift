import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import AscendApp

/// Renders the completion summary a climber actually lands on after a routine session, and writes
/// the images out for review. Assertions cover the copy; the images cover the part a human has to
/// judge — that a session which forfeited credit never *reads* as a completion.
///
/// The summary is driven end to end from `ActiveRoutineViewModel` through the same argument
/// mapping `ActiveRoutineView.routineCompletionSummary` uses, so the images show the real screen
/// rather than a hand-built presentation.
///
/// Images land in `ASCEND_EVIDENCE_DIR` when it is set, and in the test host's temporary directory
/// otherwise; either way the path is logged. Nothing reads them back, so these are evidence rather
/// than golden-image assertions.
@MainActor
struct RoutineSkipSummaryRenderEvidenceTests {
    /// A climber who skipped an interval barely stepped; one who ran the routine honestly did.
    private static let skippedSessionSteps = 14
    private static let honestSessionSteps = 902

    /// The rendered view — and the workout it holds — stays alive past the render call. Letting the
    /// container deallocate resets its context and traps the next access, so the containers outlive
    /// the tests that made them.
    private static var retainedContainers: [ModelContainer] = []

    // MARK: - After the fix

    /// The climber skipped the opening interval and let the rest run out. The session still reaches
    /// the end of the plan, so before the fix it banked a completion; now it reads as forfeited.
    @Test
    func skippedSessionSummaryReadsAsEndedAndShowsNoRank() async throws {
        let viewModel = await makeViewModel(skippedIntervals: 1)

        #expect(viewModel.didSkipInterval)
        #expect(viewModel.resolvedStopReason == .skipped)
        #expect(viewModel.countsAsCompletion == false)

        // The rank the leaderboard fetch already resolved during the live session is deliberately
        // withheld: a forfeited session holds no standing, so the summary must not render one.
        #expect(viewModel.completionLeaderboardRank == nil)
        #expect(viewModel.completionLeaderboardContext == nil)

        let presentation = viewModel.completionSummaryPresentation
        #expect(presentation.rankingLabel == "ROUTINE")
        #expect(presentation.unrankedValueText == "Incomplete")
        #expect(presentation.completedDetail == "SESSION ENDED")

        let screen = try renderSummary(
            for: viewModel,
            workout: makeWorkout(steps: Self.skippedSessionSteps),
            named: "routine-summary-skipped-after"
        )

        // The whole screen, not one card: the ranking card always denied the completion, and the
        // achievement card underneath it went on claiming one anyway.
        #expect(screen.contains("SESSION ENDED"))
        #expect(screen.contains("Incomplete"))
        #expect(screen.contains("CLIMB COMPLETE") == false)
        #expect(screen.contains { $0.localizedCaseInsensitiveContains("complete") && $0 != "Incomplete" } == false)
    }

    /// The control: the climber stepped through every interval, so the session keeps its standing.
    @Test
    func honestCompletionSummaryStillClaimsTheCompletionAndItsRank() async throws {
        let viewModel = await makeViewModel(skippedIntervals: 0)

        #expect(viewModel.didSkipInterval == false)
        #expect(viewModel.resolvedStopReason == .targetReached)
        #expect(viewModel.countsAsCompletion)
        #expect(viewModel.completionLeaderboardRank == 3)
        #expect(viewModel.completionLeaderboardTotal == 12)

        let presentation = viewModel.completionSummaryPresentation
        #expect(presentation.rankingLabel == "ROUTINE RANK")
        #expect(presentation.completedDetail == "ROUTINE COMPLETE")

        let screen = try renderSummary(
            for: viewModel,
            workout: makeWorkout(steps: Self.honestSessionSteps),
            named: "routine-summary-completed-after"
        )

        // The forfeit copy is gated to forfeited sessions, so an honest run keeps its claim.
        #expect(screen.contains("CLIMB COMPLETE"))
        #expect(screen.contains("SESSION ENDED") == false)
        #expect(screen.contains("Incomplete") == false)
    }

    // MARK: - Before the fix

    /// The same skipped session as `skippedSessionSummaryReadsAsEndedAndShowsNoRank`, rendered with
    /// the arguments the base commit's call site hardcoded: the label, the completion copy and the
    /// rank were all unconditional. The image reproduces the reported screen — a climber who barely
    /// stepped is told they completed the routine and shown a podium-adjacent rank for it.
    @Test
    func skippedSessionSummaryBeforeClaimedACompletionAndARank() async throws {
        let viewModel = await makeViewModel(skippedIntervals: 1)
        let workout = makeWorkout(steps: Self.skippedSessionSteps)
        let container = try makeContainer(inserting: workout)

        // Base-commit values: `routine.source.isTemplate` was the only gate on the rank, and the
        // completion copy was passed as literals with no stop reason involved.
        let baseRank = 3
        let baseTotal = 12

        // Passing no achievement override is exactly what the base commit did, so the card falls
        // back to its unconditional completion copy.
        let screen = try render(
            LiveClimbCompletionSummaryView(
                climb: nil,
                workout: workout,
                leaderboardRank: baseRank,
                leaderboardTotal: baseTotal,
                allowsRatingPrompt: false,
                leaderboardContext: RoutineReplayLeaderboardContextBuilder.context(for: makeRoutine()),
                rankingLabelOverride: "ROUTINE RANK",
                completedDetailOverride: "ROUTINE COMPLETE",
                unrankedValueText: "Complete",
                unrankedDetailText: "ROUTINE COMPLETE",
                showsPendingRankingState: true,
                onDone: {}
            )
            .modelContainer(container),
            named: "routine-summary-skipped-before"
        )

        // Pins the copy the fixed screen must no longer show. It also keeps the negative assertions
        // in the tests above honest: this proves the rendered screen really does publish these
        // strings, so their absence there is a fix rather than an empty read.
        #expect(screen.contains("CLIMB COMPLETE"))

        // The session the old screen called complete is the one the fix now forfeits.
        #expect(viewModel.completionStopReason == .skipped)
    }

    // MARK: - Fixtures

    private func makeViewModel(skippedIntervals: Int) async -> ActiveRoutineViewModel {
        let routine = makeRoutine()
        let viewModel = ActiveRoutineViewModel(
            routine: routine,
            leaderboardService: StubLiveReplayLeaderboardService(
                window: makeWindow(for: routine)
            )
        )

        // A live session has already fetched a replay window by the time it ends, so the rank the
        // summary would show exists on the view model either way. Only the stop reason gates it.
        viewModel.phase = .complete
        viewModel.timelineElapsed = routine.totalDuration
        viewModel.actualElapsed = routine.totalDuration
        await viewModel.refreshReplayLeaderboardIfNeeded(force: true)

        // Skipping short of the final interval leaves the session running, which is exactly the
        // laundering path session-level taint closes: skip early, let the last interval elapse.
        for _ in 0..<skippedIntervals {
            viewModel.skipInterval()
        }

        return viewModel
    }

    private func makeRoutine() -> Routine {
        Routine(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            name: "Pyramid Climb",
            source: .builtin,
            intervals: [
                RoutineInterval(duration: 60, intensityValue: 8, order: 0),
                RoutineInterval(duration: 90, intensityValue: 12, order: 1),
                RoutineInterval(duration: 60, intensityValue: 16, order: 2)
            ],
            templateId: "pyramid_climb"
        )
    }

    private func makeWorkout(steps: Int) -> Workout {
        Workout(
            name: "Pyramid Climb",
            date: Date(timeIntervalSince1970: 1_784_284_800),
            duration: 210,
            steps: steps,
            floors: steps / 16,
            source: .headphoneMotion
        )
    }

    private func makeWindow(for routine: Routine) -> LiveReplayLeaderboardWindow {
        let context = RoutineReplayLeaderboardContextBuilder.context(for: routine)
        let names = ["Dana R.", "Priya S.", "Marcus T."]

        return LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 0,
            currentSteps: Self.skippedSessionSteps,
            fetchedAt: Date(timeIntervalSince1970: 1_784_284_800),
            rows: names.indices.map { index in
                LiveReplayLeaderboardRow(
                    id: "row-\(index)",
                    rank: index + 1,
                    displayName: names[index],
                    avatarToken: String(names[index].prefix(1)),
                    photoURL: nil,
                    stepsAtBucket: 1_100 - (index * 100),
                    finalSteps: 1_100 - (index * 100),
                    deltaFromUser: 0,
                    isCurrentUser: false,
                    isPersonalBest: false,
                    completionDurationSeconds: 210,
                    userId: "user-\(index)"
                )
            },
            currentUserRank: 3,
            totalClimbers: 12
        )
    }

    private func makeContainer(inserting workout: Workout) throws -> ModelContainer {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.insert(workout)
        Self.retainedContainers.append(container)
        return container
    }

    // MARK: - Rendering

    /// Mirrors `ActiveRoutineView.routineCompletionSummary` so the image shows the shipped mapping.
    @discardableResult
    private func renderSummary(
        for viewModel: ActiveRoutineViewModel,
        workout: Workout,
        named name: String
    ) throws -> [String] {
        let container = try makeContainer(inserting: workout)
        let presentation = viewModel.completionSummaryPresentation

        return try render(
            LiveClimbCompletionSummaryView(
                climb: nil,
                workout: workout,
                leaderboardRank: viewModel.completionLeaderboardRank,
                leaderboardTotal: viewModel.completionLeaderboardTotal,
                allowsRatingPrompt: false,
                leaderboardContext: viewModel.completionLeaderboardContext,
                rankingLabelOverride: presentation.rankingLabel,
                completedDetailOverride: presentation.completedDetail,
                unrankedValueText: presentation.unrankedValueText,
                unrankedDetailText: presentation.unrankedDetailText,
                showsPendingRankingState: presentation.showsPendingRankingState,
                achievementTitleOverride: presentation.achievementTitleOverride,
                achievementIconNameOverride: presentation.achievementIconNameOverride,
                onDone: {}
            )
            .modelContainer(container),
            named: name
        )
    }

    /// Hosted in a real window rather than run through `ImageRenderer`: the summary body lives in a
    /// `ScrollView`, which `ImageRenderer` renders as empty space, and the ranking copy under test
    /// is inside it.
    ///
    /// The rendered copy does not depend on the `.task` a hosted view runs. The summary resolves its
    /// rank from the passed-in `leaderboardRank` first, so an unauthenticated fetch that fails or
    /// never returns cannot change what the image shows.
    ///
    /// Returns every string the rendered screen exposes to VoiceOver, so a test can assert on what
    /// the climber is actually told rather than on the inputs it passed in.
    @discardableResult
    private func render(_ view: some View, named name: String) throws -> [String] {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 700)
        let controller = UIHostingController(
            rootView: view
                .environment(\.colorScheme, .dark)
                .frame(width: bounds.width, height: bounds.height)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = bounds
        controller.view.backgroundColor = .black

        // The window has to belong to the host app's scene: an unattached window never gets a
        // screen update, and `drawHierarchy` snapshots it blank.
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "No window scene — the test bundle needs its app host to render"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = bounds
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        // Let SwiftUI commit its layout before the snapshot.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        window.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)

        // Logged so the image is findable inside the simulator container when no
        // ASCEND_EVIDENCE_DIR was provided.
        print("Rendered routine skip evidence: \(url.path())")

        return renderedText(in: window)
    }

    /// Walks the hosted hierarchy and collects the text it publishes. SwiftUI draws `Text` into
    /// backing views that carry no readable string, so the accessibility tree is what makes the
    /// rendered copy assertable without diffing pixels.
    private func renderedText(in root: NSObject) -> [String] {
        var found: [String] = []

        func visit(_ node: NSObject) {
            if let label = node.accessibilityLabel {
                found.append(label)
            }

            if let value = node.accessibilityValue {
                found.append(value)
            }

            let elementCount = node.accessibilityElementCount()
            if elementCount != NSNotFound && elementCount > 0 {
                for index in 0..<elementCount {
                    if let child = node.accessibilityElement(at: index) as? NSObject {
                        visit(child)
                    }
                }
            }

            if let view = node as? UIView {
                view.subviews.forEach(visit)
            }
        }

        visit(root)
        return found
    }
}

/// Serves one prefetched replay window. Every other call is unreachable from the completion
/// summary, so it fails loudly rather than returning a fixture that could mask a new dependency.
private struct StubLiveReplayLeaderboardService: LiveReplayLeaderboardServicing {
    let window: LiveReplayLeaderboardWindow

    struct NotStubbed: Error {}

    func refreshIfNeeded(
        context: LiveReplayLeaderboardContext,
        elapsedSeconds: Int,
        currentSteps: Int,
        force: Bool
    ) async throws -> LiveReplayLeaderboardWindow? {
        window
    }

    func fetchSummary(context: LiveReplayLeaderboardContext) async throws -> LiveReplayLeaderboardSummary {
        throw NotStubbed()
    }

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval
    ) async throws -> LiveReplayCompletionRank {
        throw NotStubbed()
    }

    func fetchCompletionRankSnapshot(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) async throws -> LiveReplayCompletionRankSnapshot? {
        throw NotStubbed()
    }

    func fetchPublishStatus(workoutId: String) async throws -> LiveReplayPublishStatus? {
        throw NotStubbed()
    }

    func fetchCurrentUserBestCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayCurrentUserCompletion? {
        throw NotStubbed()
    }

    func fetchCurrentUserFinisherStatus(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayFinisherStatus? {
        throw NotStubbed()
    }

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?,
        forceRefresh: Bool
    ) async throws -> LiveReplayCompletionLeaderboard {
        throw NotStubbed()
    }
}
