import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// Hosts the shipping comparison layout (`ProfileComparisonContent`) from two snapshots and
/// reads it back: the Joined row, the per-climb averages, the HEART RATE section with and
/// without heart rate on each side, and the Just Climb row judged on steps. Each test proves its
/// claim off the accessibility tree, and writes the whole scroll height as a photograph when
/// `ASCEND_EVIDENCE_DIR` is set, so a reviewer can see the screen without running the app.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ProfileComparisonStatsEvidenceTests {
    private static let bioSize = CGSize(width: 402, height: 1_560)
    private static let headToHeadSize = CGSize(width: 402, height: 900)

    @Test
    func bothClimbersWithHeartRateCompareItSideBySide() async throws {
        try await host(
            viewer: Self.viewer(heartRate: ProfileHeartRateSummary(averageBpm: 141, maxBpm: 179)),
            other: Self.other(heartRate: ProfileHeartRateSummary(averageBpm: 146, maxBpm: 184)),
            tab: .bio,
            size: Self.bioSize
        ) { screen in
            let copy = try await screen.copy { $0.contains("max heart rate") }
            #expect(copy.contains("heart rate"))
            #expect(copy.contains("141 bpm") && copy.contains("146 bpm"))
            #expect(copy.contains("179 bpm") && copy.contains("184 bpm"))
            #expect(copy.contains("joined") && copy.contains("mar 2026") && copy.contains("aug 2025"))
            #expect(copy.contains("avg steps/climb") && copy.contains("1,875") && copy.contains("2,100"))
            #expect(copy.contains("avg climb time") && copy.contains("21:05") && copy.contains("23:30"))
            try screen.photograph(named: "profile-comparison-bio-heart-rate-both")
        }
    }

    @Test
    func aClimberWithoutHeartRateReadsAsADashOnTheirSide() async throws {
        try await host(
            viewer: Self.viewer(heartRate: ProfileHeartRateSummary(averageBpm: 141, maxBpm: 179)),
            other: Self.other(heartRate: nil),
            tab: .bio,
            size: Self.bioSize
        ) { screen in
            let copy = try await screen.copy { $0.contains("max heart rate") }
            #expect(copy.contains("141 bpm") && copy.contains("179 bpm"))
            #expect(!copy.contains("146 bpm") && !copy.contains("184 bpm"))
            try screen.photograph(named: "profile-comparison-bio-heart-rate-viewer-only")
        }
    }

    @Test
    func neitherClimberWithHeartRateDrawsNoHeartRateSection() async throws {
        try await host(
            viewer: Self.viewer(heartRate: nil),
            other: Self.other(heartRate: nil),
            tab: .bio,
            size: Self.bioSize
        ) { screen in
            let copy = try await screen.copy { $0.contains("avg steps/min") }
            #expect(!copy.contains("heart rate"))
            #expect(!copy.contains("bpm"))
            #expect(copy.contains("avg steps/climb") && copy.contains("avg climb time"))
            try screen.photograph(named: "profile-comparison-bio-no-heart-rate")
        }
    }

    @Test
    func theJustClimbRowIsJudgedOnMostSteps() async throws {
        try await host(
            viewer: Self.viewer(heartRate: nil),
            other: Self.other(heartRate: nil),
            tab: .headToHead,
            size: Self.headToHeadSize
        ) { screen in
            let copy = try await screen.copy { $0.contains("empire state building") }
            #expect(copy.contains("just climb") && copy.contains("most steps"))
            #expect(copy.contains("3,120") && copy.contains("4,410"))
            try screen.photograph(named: "profile-comparison-head-to-head-just-climb")
        }
    }

    // MARK: - Hosting

    private func host(
        viewer: ProfileSnapshot,
        other: ProfileSnapshot,
        tab: ProfileComparisonTab,
        size: CGSize,
        _ body: @MainActor (HostedScreen) async throws -> Void
    ) async throws {
        let content = ProfileComparisonContent(
            viewerIdentity: Self.identity(userId: "viewer", name: "Maya Chen", isCurrentUser: true),
            otherIdentity: Self.identity(userId: "other", name: "Dominic Reyes", isCurrentUser: false),
            viewer: viewer,
            otherUser: other,
            comparison: ProfileSnapshotBuilder.comparison(viewer: viewer, otherUser: other),
            headToHeadResults: ProfileSnapshotBuilder.headToHeadResults(
                viewer: viewer,
                otherUser: other,
                climbs: []
            ),
            measurementSystem: .imperial,
            isViewerLoading: false,
            isOtherLoading: false,
            selectedTab: .constant(tab)
        )
        .frame(width: size.width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ProfileVisualStyle.background)

        try await RenderedScreen.host(content, size: size, body)
    }

    private static func identity(userId: String, name: String, isCurrentUser: Bool) -> ResolvedUserIdentity {
        ResolvedUserIdentity.Resolver.resolve(
            userId: userId,
            displayName: name,
            photoURL: nil,
            isCurrentUser: isCurrentUser,
            blockedUserIds: [],
            isBlockListHydrated: true
        )
    }

    // MARK: - Fixtures

    private static func viewer(heartRate: ProfileHeartRateSummary?) -> ProfileSnapshot {
        snapshot(
            userId: "viewer",
            demographics: ProfileDemographicsSnapshot(
                userId: "viewer",
                age: 29,
                weightKg: 61,
                heightCm: 168,
                joinedAt: date("2026-03-14")
            ),
            stats: stats(
                climbs: 38,
                stepsPerClimb: 1_875,
                secondsPerClimb: 1_265,
                bestStreak: 6,
                mostSteps: 3_120,
                heartRate: heartRate,
                achievements: ProfileAchievementCounts(top1: 1, top3: 2, top10: 5, top100: 11)
            ),
            workouts: [
                landmark(id: "v-esb", name: "Empire State Building", steps: 1_576, seconds: 1_052, on: "2026-09-20"),
                landmark(id: "v-needle", name: "Space Needle", steps: 848, seconds: 611, on: "2026-09-12"),
                landmark(id: "v-liberty", name: "Statue of Liberty", steps: 354, seconds: 219, on: "2026-08-30")
            ]
        )
    }

    private static func other(heartRate: ProfileHeartRateSummary?) -> ProfileSnapshot {
        snapshot(
            userId: "other",
            demographics: ProfileDemographicsSnapshot(
                userId: "other",
                age: 32,
                weightKg: 80.7,
                heightCm: 181,
                joinedAt: date("2025-08-25")
            ),
            stats: stats(
                climbs: 47,
                stepsPerClimb: 2_100,
                secondsPerClimb: 1_410,
                bestStreak: 18,
                mostSteps: 4_410,
                heartRate: heartRate,
                achievements: ProfileAchievementCounts(top1: 3, top3: 11, top10: 18, top100: 31)
            ),
            workouts: [
                landmark(id: "o-esb", name: "Empire State Building", steps: 1_576, seconds: 1_118, on: "2026-09-18"),
                landmark(id: "o-needle", name: "Space Needle", steps: 848, seconds: 574, on: "2026-09-02"),
                landmark(id: "o-liberty", name: "Statue of Liberty", steps: 354, seconds: 237, on: "2026-08-21")
            ]
        )
    }

    private static func snapshot(
        userId: String,
        demographics: ProfileDemographicsSnapshot,
        stats: ProfileStatsSnapshot,
        workouts: [ProfileWorkoutSummary]
    ) -> ProfileSnapshot {
        ProfileSnapshotBuilder.makeRemoteSnapshot(
            demographics: demographics,
            stats: stats,
            achievements: ProfileAchievementLadder(bandedCounters: stats.achievementCounts),
            standings: [],
            workoutSummaries: workouts,
            firstAscentsHeld: [],
            openFirstAscents: [],
            climbs: []
        )
    }

    private static func stats(
        climbs: Int,
        stepsPerClimb: Int,
        secondsPerClimb: Int,
        bestStreak: Int,
        mostSteps: Int,
        heartRate: ProfileHeartRateSummary?,
        achievements: ProfileAchievementCounts
    ) -> ProfileStatsSnapshot {
        let steps = climbs * stepsPerClimb
        let seconds = climbs * secondsPerClimb
        return ProfileStatsSnapshot(
            totalClimbsCompleted: climbs / 2,
            totalFirstAscents: 0,
            achievementCounts: achievements,
            mostCompletedClimbId: nil,
            currentStreakWeeks: 2,
            bestStreakWeeks: bestStreak,
            prMostSteps: mostSteps,
            prLongestClimbSeconds: secondsPerClimb * 2,
            prHighestSPM: 104,
            lifetimeTotalSteps: steps,
            lifetimeDurationSeconds: seconds,
            totalClimbs: climbs,
            averageStepsPerMinute: Double(steps) / (Double(seconds) / 60),
            heartRate: heartRate
        )
    }

    private static func landmark(
        id: String,
        name: String,
        steps: Int,
        seconds: Int,
        on day: String
    ) -> ProfileWorkoutSummary {
        ProfileWorkoutSummary(
            id: id,
            name: name,
            startedAt: date(day),
            durationSeconds: TimeInterval(seconds),
            steps: steps,
            source: .headphoneMotion,
            climbId: name.lowercased().replacing(" ", with: "-"),
            climbTier: .common,
            climbCompletionStatus: .completed,
            climbCompletionDurationSeconds: seconds
        )
    }

    private static func date(_ day: String) -> Date {
        (try? Date("\(day)T12:00:00Z", strategy: .iso8601)) ?? .distantPast
    }
}
