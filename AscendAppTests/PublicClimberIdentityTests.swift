import Foundation
@preconcurrency import FirebaseFirestore
import Testing
@testable import AscendApp

struct PublicClimberIdentityTests {
    @Test
    func stableSystemHandleUsesOnlyTheApprovedTokenAlphabet() throws {
        let first = PublicClimberIdentity.systemHandle(for: "user-123")
        let second = PublicClimberIdentity.systemHandle(for: "user-123")

        #expect(first == "Climber QRN9QT")
        #expect(second == first)
        #expect(first.wholeMatch(of: /Climber [2346789AEFJMNQRT]{6}/) != nil)
        #expect(PublicClimberIdentity.systemHandle(for: "user-456") == "Climber 6JN7TM")
    }

    @Test
    func invalidIdentifiersResolveToAnonymousClimber() {
        #expect(PublicClimberIdentity.systemHandle(for: nil) == "Anonymous Climber")
        #expect(PublicClimberIdentity.systemHandle(for: "  ") == "Anonymous Climber")
        #expect(PublicClimberIdentity.systemHandle(for: "user\n123") == "Anonymous Climber")
        #expect(PublicClimberIdentity.systemHandle(for: String(repeating: "a", count: 129)) == "Anonymous Climber")
    }

    /// The fallback handle gates publication: `DisplayNamePolicy` runs on it in
    /// the profile transaction and `isAllowedDisplayName` runs on it again in
    /// `firestore.rules`. A token either policy rejects would leave that uid
    /// permanently unable to publish a profile or write a leaderboard row.
    @Test
    func everySampledFallbackHandlePassesDisplayNameScreening() {
        for index in 0..<1_000 {
            let handle = PublicClimberIdentity.systemHandle(
                for: "screening-user-\(index)"
            )
            let token = Array(handle.dropFirst("Climber ".count))

            #expect(DisplayNamePolicy.isAllowed(handle), "rejected \(handle)")
            #expect(token.count == 6)
            #expect(
                zip(token, token.dropFirst()).allSatisfy { $0 != $1 },
                "repeated character in \(handle)"
            )
        }
    }

    /// Exhaustive over the alphabet: no pair of token characters, however the
    /// generator interleaves them, can spell a screened term or a letter run.
    @Test
    func everyTokenAlphabetPairProducesAnAllowedHandle() {
        for first in PublicClimberIdentity.tokenAlphabet {
            for second in PublicClimberIdentity.tokenAlphabet where first != second {
                let token = String([first, second, first, second, first, second])

                #expect(
                    DisplayNamePolicy.isAllowed("Climber \(token)"),
                    "rejected Climber \(token)"
                )
            }
        }
    }

    @Test
    func sampledAccountsHaveStableDistinctHandles() {
        let handles = (0..<1_000).map { index in
            PublicClimberIdentity.systemHandle(for: "sample-user-\(index)")
        }

        #expect(Set(handles).count == handles.count)
    }

    @Test
    func realOtherUserUsesAccountAuthoredNameAndPhoto() {
        let publicPhoto = URL(string: "https://example.com/public-profile.jpg")
        let identity = PublicClimberIdentity.resolve(
            userId: "user-123",
            storedDisplayName: "Maya Chen",
            storedPhotoURL: publicPhoto,
            storedAvatarToken: "PN"
        )

        #expect(identity.displayName == "Maya Chen")
        #expect(identity.photoURL == publicPhoto)
        #expect(identity.avatarToken == "MC")
        #expect(identity.usesGenericAvatar == false)
    }

    @Test
    func missingAccountAuthoredNameFallsBackToStableHandle() {
        let identity = PublicClimberIdentity.resolve(
            userId: "user-123",
            storedDisplayName: "  ",
            storedPhotoURL: nil
        )

        #expect(identity.displayName == "Climber QRN9QT")
        #expect(identity.photoURL == nil)
        #expect(identity.avatarToken == "CQ")
        #expect(identity.usesGenericAvatar)
    }

    @Test
    func currentUserKeepsPrivatePhotoAndYouLabel() {
        let privatePhoto = URL(string: "https://example.com/private-profile.jpg")
        let identity = PublicClimberIdentity.resolve(
            userId: "user-123",
            storedDisplayName: "Private Name",
            storedPhotoURL: privatePhoto,
            isCurrentUser: true,
            currentUserPhotoURL: privatePhoto
        )

        #expect(identity.displayName == "You")
        #expect(identity.photoURL == privatePhoto)
        #expect(identity.avatarToken == "YOU")
        #expect(identity.usesGenericAvatar == false)
    }

    @Test
    func trustedSyntheticAndDeletedIdentitiesKeepTheirSpecialPresentation() {
        let syntheticPhoto = URL(string: "https://example.com/synthetic.jpg")
        let synthetic = PublicClimberIdentity.resolve(
            userId: "seeded:pack:everest:0",
            storedDisplayName: "Maya C.",
            storedPhotoURL: syntheticPhoto,
            storedAvatarToken: "MC",
            isSynthetic: true
        )
        let deleted = PublicClimberIdentity.resolve(
            userId: "deleted-user",
            storedDisplayName: "Anonymous Climber",
            storedPhotoURL: syntheticPhoto
        )

        #expect(synthetic.displayName == "Maya C.")
        #expect(synthetic.photoURL == syntheticPhoto)
        #expect(synthetic.avatarToken == "MC")
        #expect(synthetic.usesGenericAvatar == false)
        #expect(deleted.displayName == "Anonymous Climber")
        #expect(deleted.photoURL == nil)
        #expect(deleted.usesGenericAvatar)
    }

    @Test
    func deletedProfileSeedRemainsAnonymousWhenRemoteProfileIsMissing() throws {
        let initialIdentity = ResolvedUserIdentity.Resolver.resolve(
            userId: "deleted-user",
            displayName: PublicClimberIdentity.anonymousDisplayName,
            photoURL: nil,
            isCurrentUser: false,
            blockedUserIds: [],
            isBlockListHydrated: true
        )

        #expect(initialIdentity.isHidden == false)
        let seededIdentity = try #require(
            ProfileScreenViewModel.initialOtherUserIdentity(
                userId: "deleted-user",
                initialIdentity: initialIdentity
            )
        )
        let renderedIdentity = CrossUserIdentityAdapter.profileIdentity(
            seededIdentity,
            isCurrentUser: false,
            blockedUserIds: [],
            isBlockListHydrated: true
        )

        #expect(renderedIdentity.displayName == PublicClimberIdentity.anonymousDisplayName)
        #expect(renderedIdentity.photoURL == nil)
    }

    @Test
    func blockedProfileSeedsNothingSoTheResolvedPlaceholderKeepsRendering() {
        let realPhotoURL = URL(string: "https://example.com/real-photo.jpg")
        let initialIdentity = ResolvedUserIdentity.Resolver.resolve(
            userId: "blocked-user",
            displayName: "Real Name",
            photoURL: realPhotoURL,
            isCurrentUser: false,
            blockedUserIds: ["blocked-user"],
            isBlockListHydrated: true
        )

        #expect(initialIdentity.isHidden)
        #expect(
            ProfileScreenViewModel.initialOtherUserIdentity(
                userId: "blocked-user",
                initialIdentity: initialIdentity
            ) == nil
        )
    }

    @Test
    func demographicPublicationPreservesIdentityVersion() throws {
        let changedAt = Timestamp(seconds: 100, nanoseconds: 5)
        let identity = ProfileUserIdentity(
            userId: "user-123",
            displayName: "Maya Chen",
            photoURL: URL(string: Self.storagePhotoURL),
            age: 32
        )
        let existingData: [String: Any] = [
            "displayName": "Maya Chen",
            "photoURL": Self.storagePhotoURL,
            "identityPolicyVersion": PublicClimberIdentity.policyVersion,
            "identityChangedAt": changedAt,
            "age": 31
        ]

        #expect(
            try ProfileRepository.publicIdentityNeedsVersionAdvance(
                identity,
                existingData: existingData
            ) == false
        )
        let payload = try ProfileRepository.publicIdentityPayload(
            identity,
            advancesIdentityVersion: false
        )
        #expect(payload["identityChangedAt"] == nil)
        #expect(payload["age"] as? Int == 32)
    }

    /// A photo URL outside Firebase Storage is dropped rather than published, so
    /// the server never rejects the whole profile write over a value the client
    /// could have discarded.
    @Test
    func onlyFirebaseStoragePhotoURLsArePublishable() {
        #expect(
            PublicClimberIdentity.publishablePhotoURL(
                URL(string: Self.storagePhotoURL)
            )?.absoluteString == Self.storagePhotoURL
        )

        for candidate in [
            "https://example.com/maya.jpg",
            "http://firebasestorage.googleapis.com/v0/b/bucket/o/photo.jpg",
            "https://firebasestorage.googleapis.com.attacker.test/v0/b/b/o/x.jpg",
            "https://firebasestorage.googleapis.com/evil.jpg",
            "https://firebasestorage.googleapis.com/v0/b/bucket/o/users/plain.jpg"
        ] {
            #expect(
                PublicClimberIdentity.publishablePhotoURL(
                    URL(string: candidate)
                ) == nil,
                "published \(candidate)"
            )
        }
    }

    private static let storagePhotoURL =
        "https://firebasestorage.googleapis.com/v0/b/ascend-test.appspot.com/o/" +
        "users%2Fuser-123%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc"
}
