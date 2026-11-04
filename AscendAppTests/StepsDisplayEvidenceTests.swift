import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import AscendApp

/// A climb that carries no step count - an Apple Health stair workout whose watch saved none -
/// is stored with zero and means "unknown". These prove every surface says so: the Activity row
/// asks for the steps instead of printing `0 steps`, and no record badge celebrates it.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct StepsDisplayEvidenceTests {
    private static func container() throws -> ModelContainer {
        try RetainedModelContainer.inMemory(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            LeaderboardStats.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self
        )
    }

    private static func importedClimb(steps: Int, duration: TimeInterval, daysAgo: Int) -> Workout {
        Workout(
            name: "Stair Stepper",
            date: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
            duration: duration,
            steps: steps,
            floors: steps / 16,
            source: .appleHealth
        )
    }

    private static func summary(duration: TimeInterval, steps: Int, source: WorkoutSource) -> ProfileWorkoutSummary {
        ProfileWorkoutSummary(
            id: UUID().uuidString,
            name: "Stair Stepper",
            startedAt: Date(),
            durationSeconds: duration,
            steps: steps,
            source: source,
            climbId: nil,
            climbTier: nil,
            climbCompletionStatus: nil,
            climbCompletionDurationSeconds: nil
        )
    }

    @Test("The Activity row asks for steps on an unknown count and never prints 0 steps")
    func theActivityRowAsksForSteps() async throws {
        let unknown = Self.importedClimb(steps: 0, duration: 1_474, daysAgo: 3)
        let known = Self.importedClimb(steps: 4_912, duration: 3_770, daysAgo: 4)
        #expect(unknown.isMissingSteps && !known.isMissingSteps)

        try await RenderedScreen.host(
            VStack(spacing: 12) {
                WorkoutRowView(workout: unknown)
                WorkoutRowView(workout: known)
            }
            .padding(20)
            .frame(width: 402)
            .background(Color.black),
            size: CGSize(width: 402, height: 340)
        ) { screen in
            let copy = try await screen.copy { $0.contains("4,912") }

            #expect(copy.contains("add steps"), "\(copy)")
            #expect(copy.contains("4,912 steps"), "\(copy)")
            #expect(!copy.contains("0 steps"), "an unknown count is not a climb of nothing: \(copy)")
            #expect(copy.contains("24:34"), "the duration still reads: \(copy)")
            try screen.photograph(named: "steps-01-activity-rows")
        }
    }

    @Test("A climb with no steps earns no record badge until steps are in")
    func noBadgeWithoutSteps() throws {
        let container = try Self.container()
        let context = container.mainContext
        let referenceDate = Date()
        let unknown = Self.importedClimb(steps: 0, duration: 2_000, daysAgo: 1)
        let others = [
            Self.importedClimb(steps: 5_000, duration: 3_600, daysAgo: 2),
            Self.importedClimb(steps: 4_000, duration: 2_900, daysAgo: 3),
            Self.importedClimb(steps: 3_000, duration: 1_200, daysAgo: 4)
        ]
        ([unknown] + others).forEach(context.insert)
        try context.save()
        try BestEffortCacheStore.rebuild(modelContext: context, referenceDate: referenceDate)

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let entries = try context.fetch(FetchDescriptor<BestEffortCacheEntry>())
        let snapshot = BestEffortCacheSnapshot(entries: entries, workouts: workouts)

        #expect(snapshot.efforts(for: unknown).isEmpty, "no badge on a climb with unknown steps")
        #expect(snapshot.primaryEffortsByWorkoutID()[unknown.id] == nil)
        #expect(snapshot.primaryEffort(for: others[0]) != nil, "a finished climb keeps its badge")

        unknown.steps = 3_300
        try context.save()
        try BestEffortCacheStore.rebuildIfNeeded(modelContext: context, referenceDate: referenceDate)
        let filled = BestEffortCacheSnapshot(
            entries: try context.fetch(FetchDescriptor<BestEffortCacheEntry>()),
            workouts: workouts
        )
        #expect(!filled.efforts(for: unknown).isEmpty, "once steps are in, the badge returns: it is a climb now")
    }

    @Test("A climb with no steps holds no rank, so finished climbs are not ranked around it")
    func finishedClimbsRankWithoutAClimbWithNoSteps() throws {
        let container = try Self.container()
        let context = container.mainContext
        let unknown = Self.importedClimb(steps: 0, duration: 7_200, daysAgo: 1)
        let longest = Self.importedClimb(steps: 5_000, duration: 3_600, daysAgo: 2)
        let shorter = Self.importedClimb(steps: 4_000, duration: 2_880, daysAgo: 3)
        [unknown, longest, shorter].forEach(context.insert)
        try context.save()
        try BestEffortCacheStore.rebuild(modelContext: context, referenceDate: Date())

        let entries = try context.fetch(FetchDescriptor<BestEffortCacheEntry>())
        #expect(!entries.contains { $0.workoutID == unknown.id }, "the cache holds no rank for it at all")

        let snapshot = BestEffortCacheSnapshot(entries: entries, workouts: [unknown, longest, shorter])
        let board = snapshot.rankedEfforts(for: .longestClimb)
        #expect(board.map(\.workout.id) == [longest.id, shorter.id])
        #expect(board.map(\.rank) == [1, 2], "the longest finished climb is first, not second to a hidden one")
    }

    @Test("A climb with no steps feeds none of the Profile's records")
    func theProfileRecordsSkipAClimbWithNoSteps() {
        let stats = ProfileSnapshotBuilder.statsSnapshot(
            workouts: [
                Self.importedClimb(steps: 0, duration: 7_200, daysAgo: 1),
                Self.importedClimb(steps: 5_000, duration: 3_600, daysAgo: 2)
            ],
            completedAttempts: [],
            completedCount: 0,
            achievements: .zero
        )

        #expect(stats.prLongestClimbSeconds == 3_600)
        #expect(stats.prMostSteps == 5_000)
    }

    @Test("Another climber's Profile takes no longest climb from a climb with no steps")
    func theRemoteProfileFallbackSkipsAClimbWithNoSteps() {
        let remote = ProfileSnapshotBuilder.statsSnapshot(
            workouts: [Self.importedClimb(steps: 0, duration: 7_200, daysAgo: 1)],
            completedAttempts: [],
            completedCount: 0,
            achievements: .zero
        )
        #expect(remote.prLongestClimbSeconds == 0)

        func merged(_ summaries: [ProfileWorkoutSummary]) -> ProfileStatsSnapshot {
            ProfileScreenViewModel.mergedStats(
                remote: remote,
                fallback: ProfileScreenViewModel.fallbackStatsSnapshot(
                    summaries: summaries,
                    firstAscentCount: 0,
                    achievementCounts: .zero
                )
            )
        }

        let noSteps = Self.summary(duration: 7_200, steps: 0, source: .appleHealth)
        #expect(merged([noSteps]).prLongestClimbSeconds == 0, "no record for a climb with no steps")
        #expect(merged([noSteps]).lifetimeDurationSeconds == 7_200, "the time still counts: it was climbed")
        #expect(merged([noSteps]).averageStepsPerMinute == 0, "and it gives no pace")
        #expect(
            merged([noSteps, Self.summary(duration: 3_000, steps: 5_000, source: .appleHealth)]).averageStepsPerMinute == 100,
            "its minutes stay out of the fallback average"
        )
        #expect(
            merged([noSteps, Self.summary(duration: 3_600, steps: 5_000, source: .appleHealth)]).prLongestClimbSeconds == 3_600,
            "the longest climb with steps holds it"
        )
        #expect(
            merged([Self.summary(duration: 1_800, steps: 0, source: .headphoneMotion)]).prLongestClimbSeconds == 1_800,
            "a live climb's zero is a measurement"
        )
    }

    @Test("Copy Workout Text states no steps for a climb whose steps are unknown")
    func copiedTextOmitsUnknownSteps() {
        func text(for workout: Workout) -> String {
            workoutShareText(for: workout, measurementSystem: .imperial, stepHeight: 8)
        }

        let unknown = text(for: Self.importedClimb(steps: 0, duration: 1_474, daysAgo: 1))
        #expect(!unknown.contains("Steps:"), "\(unknown)")
        #expect(!unknown.contains("Pace:"), "\(unknown)")
        #expect(unknown.contains("Duration:"), "\(unknown)")

        #expect(text(for: Self.importedClimb(steps: 4_912, duration: 3_770, daysAgo: 1)).contains("Steps: 4,912"))

        let live = Workout(name: "Live", date: Date(), duration: 600, steps: 0, floors: 0, source: .headphoneMotion)
        #expect(text(for: live).contains("Steps: 0"), "a live climb's zero is a measurement")
    }

    @Test("A climb with no steps offers Add steps where Share was, and only then")
    func theMenuOffersAddStepsInPlaceOfShare() async throws {
        var shared = 0
        var addedSteps = 0

        try await RenderedScreen.host(
            VStack(spacing: 24) {
                WorkoutDetailShareOrAddStepsAction(
                    isMissingSteps: true,
                    share: { shared += 1 },
                    addSteps: { addedSteps += 1 }
                )
            }
            .frame(width: 402, height: 200),
            size: CGSize(width: 402, height: 200)
        ) { screen in
            let copy = try await screen.copy { $0.contains("add steps") }
            #expect(!copy.contains("share"), "\(copy)")
            try activateAccessibilityElement(labelled: "Add steps", in: screen.root)
        }
        #expect(addedSteps == 1)
        #expect(shared == 0)

        try await RenderedScreen.host(
            VStack(spacing: 24) {
                WorkoutDetailShareOrAddStepsAction(
                    isMissingSteps: false,
                    share: { shared += 1 },
                    addSteps: { addedSteps += 1 }
                )
            }
            .frame(width: 402, height: 200),
            size: CGSize(width: 402, height: 200)
        ) { screen in
            let copy = try await screen.copy { $0.contains("share") }
            #expect(!copy.contains("add steps"), "\(copy)")
        }
    }
}
