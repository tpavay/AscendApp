import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

struct LeaderboardIdentityLifecycleTests {
    @Test(arguments: ["pending_public_profile", "deleted"])
    func serverMaskedIdentityKeepsRowAndRankingFields(identityState: String) throws {
        let stats = try #require(
            LeaderboardRepository.shared.parseStat(
                leaderboardDocument(identityState: identityState)
            )
        )
        let entry = CrossUserIdentityAdapter.leaderboardEntry(
            from: stats,
            rank: 4,
            value: stats.value(for: .climb),
            formattedValue: "1,200",
            isTied: false,
            currentUserId: "viewer",
            currentUserPhotoURL: nil
        )
        let resolved = CrossUserIdentityAdapter.leaderboardEntry(
            entry,
            blockedUserIds: [],
            isBlockListHydrated: true
        )

        #expect(resolved.identity.displayName == "Anonymous Climber")
        #expect(resolved.identity.photoURL == nil)
        #expect(resolved.rank == 4)
        #expect(resolved.value == 1_200)
        #expect(stats.age == 31)
        #expect(stats.locationCity == "Chicago")
    }

    @Test
    func publishedIdentityRequiresTimestampAndLegacyLifecycleIsRejected() {
        var missingTimestamp = leaderboardDocument(identityState: "published")
        missingTimestamp["displayName"] = "Maya Chen"
        missingTimestamp["identityChangedAt"] = NSNull()
        missingTimestamp["photoURL"] = "https://example.com/maya.jpg"

        var legacy = leaderboardDocument(identityState: "published")
        legacy.removeValue(forKey: "identityState")

        #expect(LeaderboardRepository.shared.parseStat(missingTimestamp) == nil)
        #expect(LeaderboardRepository.shared.parseStat(legacy) == nil)
    }

    @Test
    func migratedLegacyAnonymousShapeParsesAndRemainsRanked() throws {
        var migrated = leaderboardDocument(identityState: "deleted")
        migrated["displayName"] = "Anonymous Climber"
        migrated["photoURL"] = ""
        migrated["identityPolicyVersion"] = 1
        migrated["identityChangedAt"] = NSNull()

        let stats = try #require(
            LeaderboardRepository.shared.parseStat(migrated)
        )
        let entry = CrossUserIdentityAdapter.leaderboardEntry(
            from: stats,
            rank: 4,
            value: stats.value(for: .climb),
            formattedValue: "1,200",
            isTied: false,
            currentUserId: "viewer",
            currentUserPhotoURL: nil
        )
        let resolved = CrossUserIdentityAdapter.leaderboardEntry(
            entry,
            blockedUserIds: [],
            isBlockListHydrated: true
        )

        #expect(resolved.identity.displayName == "Anonymous Climber")
        #expect(resolved.identity.photoURL == nil)
        #expect(resolved.rank == 4)
        #expect(resolved.value == 1_200)
        #expect(stats.age == 31)
        #expect(stats.locationCity == "Chicago")
    }

    private func leaderboardDocument(
        identityState: String
    ) -> [String: Any] {
        [
            "userId": "other",
            "displayName": "Stale Real Name",
            "photoURL": "https://example.com/stale-real-photo.jpg",
            "identityPolicyVersion": 1,
            "identityChangedAt": NSNull(),
            "identityState": identityState,
            "timeFrame": "weekly",
            "schemaVersion": 2,
            "periodKey": "2026-W31",
            "periodStartAt": Timestamp(
                date: Date(timeIntervalSince1970: 1_753_660_800)
            ),
            "totalSteps": 1_200,
            "totalFloors": 75,
            "totalWorkouts": 1,
            "totalDuration": 1_800.0,
            "stepsPerMinute": 40.0,
            "lastUpdated": Timestamp(
                date: Date(timeIntervalSince1970: 1_753_747_200)
            ),
            "age": 31,
            "location_city": "Chicago",
        ]
    }
}
