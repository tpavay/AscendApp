import Foundation
import Testing
@testable import AscendApp

struct CrossUserIdentityResolverTests {
    private let realPhotoURL = URL(string: "https://example.com/real-photo.jpg")

    @Test
    func blockedIdentityReplacesOnlyUserSuppliedIdentity() {
        let resolved = CrossUserIdentityResolver.resolve(
            userId: "blocked-user",
            displayName: "Real Name",
            photoURL: realPhotoURL,
            avatarToken: "RN",
            isCurrentUser: false,
            blockedUserIds: ["blocked-user"],
            isBlockListHydrated: true
        )

        #expect(
            resolved.displayName ==
                CrossUserIdentityResolver.hiddenDisplayName(for: "blocked-user")
        )
        #expect(resolved.photoURL == nil)
        #expect(resolved.avatarToken.isEmpty)
        #expect(resolved.isHidden)
        #expect(resolved.unmoderatedDisplayName == "Real Name")
        #expect(resolved.unmoderatedPhotoURL == realPhotoURL)
    }

    @Test
    func identityStaysHiddenUntilServerBlockListHydrates() {
        let resolved = CrossUserIdentityResolver.resolve(
            userId: "other-user",
            displayName: "Real Name",
            photoURL: realPhotoURL,
            avatarToken: "RN",
            isCurrentUser: false,
            blockedUserIds: [],
            isBlockListHydrated: false
        )

        #expect(
            resolved.displayName ==
                CrossUserIdentityResolver.hiddenDisplayName(for: "other-user")
        )
        #expect(resolved.photoURL == nil)
        #expect(resolved.avatarToken.isEmpty)
        #expect(resolved.unmoderatedDisplayName == "Real Name")
        #expect(resolved.unmoderatedPhotoURL == realPhotoURL)
    }

    @Test
    func hiddenAliasIsStableAndDistinctForEachUser() {
        let first = CrossUserIdentityResolver.hiddenDisplayName(for: "blocked-user")
        let repeated = CrossUserIdentityResolver.hiddenDisplayName(for: "blocked-user")
        let second = CrossUserIdentityResolver.hiddenDisplayName(for: "another-user")

        #expect(first == repeated)
        #expect(first != second)
        #expect(first.hasPrefix("Blocked climber "))
    }

    @Test
    func hydratedUnblockedIdentityPassesThrough() {
        let resolved = CrossUserIdentityResolver.resolve(
            userId: "other-user",
            displayName: "Real Name",
            photoURL: realPhotoURL,
            avatarToken: "RN",
            isCurrentUser: false,
            blockedUserIds: [],
            isBlockListHydrated: true
        )

        #expect(resolved.displayName == "Real Name")
        #expect(resolved.photoURL == realPhotoURL)
        #expect(resolved.avatarToken == "RN")
        #expect(resolved.isHidden == false)
    }

    @Test
    func leaderboardIdentityReplacementPreservesRankAndResult() {
        let entry = LeaderboardEntry(
            userId: "blocked-user",
            displayName: "Real Name",
            photoURL: realPhotoURL,
            rank: 2,
            value: 12_345,
            formattedValue: "12,345",
            isTied: true
        )

        let hidden = entry.withProfile(displayName: "Blocked climber", photoURL: nil)

        #expect(hidden.rank == 2)
        #expect(hidden.value == 12_345)
        #expect(hidden.formattedValue == "12,345")
        #expect(hidden.isTied)
        #expect(hidden.userId == "blocked-user")
    }

    @Test
    func replayIdentityReplacementPreservesPerformanceAndDemographics() {
        let row = LiveReplayLeaderboardRow(
            id: "blocked-user",
            rank: 3,
            displayName: "Real Name",
            avatarToken: "RN",
            photoURL: realPhotoURL,
            stepsAtBucket: 900,
            finalSteps: 1_200,
            deltaFromUser: 150,
            isCurrentUser: false,
            isPersonalBest: true,
            completionDurationSeconds: 720,
            userId: "blocked-user",
            gender: "woman",
            age: 35,
            locationCity: "Chicago",
            isTied: true
        )

        let hidden = CrossUserIdentityAdapter.replayRow(
            row,
            blockedUserIds: ["blocked-user"],
            isBlockListHydrated: true
        )

        #expect(hidden.identity.displayName != "Real Name")
        #expect(hidden.identity.photoURL == nil)
        #expect(hidden.rank == 3)
        #expect(hidden.stepsAtBucket == 900)
        #expect(hidden.finalSteps == 1_200)
        #expect(hidden.deltaFromUser == 150)
        #expect(hidden.completionDurationSeconds == 720)
        #expect(hidden.gender == "woman")
        #expect(hidden.age == 35)
        #expect(hidden.locationCity == "Chicago")
        #expect(hidden.isTied)
    }
}
