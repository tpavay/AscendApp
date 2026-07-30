import Foundation
@preconcurrency import FirebaseFirestore
import Testing
@testable import AscendApp

struct PublicClimberIdentityTests {
    @Test
    func stableSystemHandleUsesOnlyTheApprovedTokenAlphabet() throws {
        let first = PublicClimberIdentity.systemHandle(for: "user-123")
        let second = PublicClimberIdentity.systemHandle(for: "user-123")

        #expect(first == "Climber 7TPMNX")
        #expect(second == first)
        #expect(first.wholeMatch(of: /Climber [A-Z2-7]{6}/) != nil)
        #expect(PublicClimberIdentity.systemHandle(for: "user-456") == "Climber ZA5MJ6")
    }

    @Test
    func invalidIdentifiersResolveToAnonymousClimber() {
        #expect(PublicClimberIdentity.systemHandle(for: nil) == "Anonymous Climber")
        #expect(PublicClimberIdentity.systemHandle(for: "  ") == "Anonymous Climber")
        #expect(PublicClimberIdentity.systemHandle(for: "user\n123") == "Anonymous Climber")
        #expect(PublicClimberIdentity.systemHandle(for: String(repeating: "a", count: 129)) == "Anonymous Climber")
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

        #expect(identity.displayName == "Climber 7TPMNX")
        #expect(identity.photoURL == nil)
        #expect(identity.avatarToken == "C7")
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
    func deletedProfileSeedRemainsAnonymousWhenRemoteProfileIsMissing() {
        let initialIdentity = ResolvedUserIdentity.Resolver.resolve(
            userId: "deleted-user",
            displayName: "Anonymous Climber",
            photoURL: nil,
            isCurrentUser: false,
            blockedUserIds: [],
            isBlockListHydrated: false
        )

        #expect(initialIdentity.isHidden)
        let seededIdentity = ProfileScreenViewModel.initialOtherUserIdentity(
            userId: "deleted-user",
            initialIdentity: initialIdentity
        )
        let renderedIdentity = CrossUserIdentityAdapter.profileIdentity(
            seededIdentity,
            isCurrentUser: false,
            blockedUserIds: [],
            isBlockListHydrated: true
        )

        #expect(renderedIdentity.displayName == "Anonymous Climber")
        #expect(renderedIdentity.photoURL == nil)
    }

    @Test
    func demographicPublicationPreservesIdentityVersion() throws {
        let changedAt = Timestamp(seconds: 100, nanoseconds: 5)
        let identity = ProfileUserIdentity(
            userId: "user-123",
            displayName: "Maya Chen",
            photoURL: URL(string: "https://example.com/maya.jpg"),
            age: 32
        )
        let existingData: [String: Any] = [
            "displayName": "Maya Chen",
            "photoURL": "https://example.com/maya.jpg",
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
}
