import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// The client half of the `home_today_activity/global` contract: what the server writes
/// (`functions/src/homeTodayActivity.ts`) is what Home reads, row for row.
struct HomeTodayActivityFeedDecoderTests {
    @Test
    func aServerDocumentDecodesNewestFirstWithIdentityAndGoal() throws {
        let feed = HomeTodayActivityFeedDecoder.feed(from: [
            "schemaVersion": 1,
            "rowCount": 2,
            "updatedAt": Timestamp(date: Date(timeIntervalSince1970: 1_000)),
            "rows": [
                [
                    "workoutId": "w2",
                    "userId": "user-b",
                    "kind": "just_climb",
                    "steps": 2_140,
                    "durationSeconds": 1_736.0,
                    "completedAt": Timestamp(date: Date(timeIntervalSince1970: 900)),
                    "publishedAt": Timestamp(date: Date(timeIntervalSince1970: 950)),
                    "justClimbGoalKind": "duration",
                    "justClimbGoalValue": 30,
                    "displayName": "Tomáš",
                    "avatarToken": "TK7",
                    "photoURL": "",
                    "identityState": "published",
                    "isSynthetic": false,
                ],
                [
                    "workoutId": "w1",
                    "userId": "user-a",
                    "kind": "live_climb",
                    "climbId": "eiffel-tower",
                    "steps": 1_665,
                    "durationSeconds": 768,
                    "completedAt": Timestamp(date: Date(timeIntervalSince1970: 800)),
                    "publishedAt": Timestamp(date: Date(timeIntervalSince1970: 810)),
                    "displayName": "Urjeta",
                    "avatarToken": "UP2",
                    "photoURL": "https://firebasestorage.googleapis.com/v0/b/bucket/o/photo",
                    "identityState": "published",
                    "isSynthetic": false,
                ],
            ],
        ])

        #expect(feed.rows.map(\.id) == ["w2", "w1"])
        #expect(feed.updatedAt == Date(timeIntervalSince1970: 1_000))

        let justClimb = try #require(feed.rows.first)
        #expect(justClimb.kind == .justClimb)
        #expect(justClimb.justClimbGoalKind == .duration)
        #expect(justClimb.justClimbGoal?.kind == .duration)
        #expect(justClimb.justClimbGoal?.durationMinutes == 30)
        #expect(justClimb.climbId == nil)

        let liveClimb = try #require(feed.rows.last)
        #expect(liveClimb.kind == .liveClimb)
        #expect(liveClimb.climbId == "eiffel-tower")
        #expect(liveClimb.durationSeconds == 768)
        #expect(liveClimb.justClimbGoal == nil)
    }

    @Test
    func aRowTheClientCannotReadIsDroppedWithoutHidingTheRest() {
        let feed = HomeTodayActivityFeedDecoder.feed(from: [
            "rows": [
                ["workoutId": "broken"],
                validRow(workoutId: "w1", kind: "routine_template", extra: ["routineTemplateId": "pyramid_climb"]),
                validRow(workoutId: "w0", kind: "some_future_kind"),
            ],
        ])

        #expect(feed.rows.map(\.id) == ["w1"])
        #expect(feed.rows.first?.routineTemplateId == "pyramid_climb")
    }

    @Test
    func aMissingDocumentIsAnEmptyFeed() {
        let feed = HomeTodayActivityFeedDecoder.feed(from: nil)
        #expect(feed == .empty)
        #expect(feed.homeRows.isEmpty)
        #expect(!feed.hasMoreThanHomeRows)
    }

    @Test
    func homeShowsThreeRowsAndSeeAllOnlyWhenTheServerHoldsMore() {
        let three = HomeTodayActivityFeed(
            rows: (0..<3).map { row(workoutId: "w\($0)") },
            updatedAt: nil
        )
        #expect(three.homeRows.count == 3)
        #expect(!three.hasMoreThanHomeRows)

        let four = HomeTodayActivityFeed(
            rows: (0..<4).map { row(workoutId: "w\($0)") },
            updatedAt: nil
        )
        #expect(four.homeRows.map(\.id) == ["w0", "w1", "w2"])
        #expect(four.hasMoreThanHomeRows)
    }

    @Test
    func markingAgainstTheSignedInClimberFlagsOnlyTheirRows() {
        let feed = HomeTodayActivityFeed(
            rows: [row(workoutId: "w1", userId: "user-a"), row(workoutId: "w2", userId: "user-b")],
            updatedAt: nil
        ).marking(currentUserId: "user-a")

        #expect(feed.rows.map(\.isCurrentUser) == [true, false])
        #expect(feed.marking(currentUserId: nil).rows.map(\.isCurrentUser) == [false, false])
    }

    @Test
    func justClimbGoalsReopenAsTheSameGoal() {
        // `JustClimbGoal` carries a fresh id, so goals compare on what the sheet re-opens.
        let steps = row(workoutId: "w", kind: .justClimb, goalKind: .steps, goalValue: 1_500)
        #expect(steps.justClimbGoal?.kind == .steps)
        #expect(steps.justClimbGoal?.stepCount == 1_500)

        let open = row(workoutId: "w", kind: .justClimb, goalKind: .open)
        #expect(open.justClimbGoal?.kind == .open)

        let liveClimb = row(workoutId: "w", kind: .liveClimb)
        #expect(liveClimb.justClimbGoal == nil)
    }

    // MARK: - Fixtures

    private func validRow(workoutId: String, kind: String, extra: [String: Any] = [:]) -> [String: Any] {
        var data: [String: Any] = [
            "workoutId": workoutId,
            "userId": "user-a",
            "kind": kind,
            "steps": 1_000,
            "durationSeconds": 600,
            "completedAt": Timestamp(date: Date(timeIntervalSince1970: 100)),
            "publishedAt": Timestamp(date: Date(timeIntervalSince1970: 110)),
            "displayName": "Ada",
            "avatarToken": "AE7",
            "photoURL": "",
            "identityState": "published",
            "isSynthetic": false,
        ]
        for (key, value) in extra {
            data[key] = value
        }
        return data
    }

    private func row(
        workoutId: String,
        userId: String = "user-a",
        kind: HomeTodayActivityKind = .liveClimb,
        goalKind: HomeTodayJustClimbGoalKind? = nil,
        goalValue: Int? = nil
    ) -> HomeTodayActivityRow {
        HomeTodayActivityRow(
            workoutId: workoutId,
            userId: userId,
            kind: kind,
            climbId: kind == .liveClimb ? "empire-state-building" : nil,
            steps: 1_000,
            durationSeconds: 600,
            completedAt: Date(timeIntervalSince1970: 100),
            publishedAt: Date(timeIntervalSince1970: 110),
            justClimbGoalKind: goalKind,
            justClimbGoalValue: goalValue,
            displayName: "Ada",
            photoURL: nil,
            avatarToken: "AE7",
            isSynthetic: false
        )
    }
}
