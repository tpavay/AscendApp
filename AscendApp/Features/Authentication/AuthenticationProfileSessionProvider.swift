import Foundation

@MainActor
protocol AuthenticationProfileSessionProviding: AnyObject {
    func cachedDisplayName() -> String?
    func cachedProfilePictureURL() -> String?
    func clearCache()
    func saveInitialUser(_ user: AuthenticatedUser) async throws
    func displayName(userID: String) async -> String?
    func profilePictureURL(userID: String) async -> String?
}

@MainActor
final class LiveAuthenticationProfileSessionProvider: AuthenticationProfileSessionProviding {
    private let repository: UserDataRepository

    init(repository: UserDataRepository = .shared) {
        self.repository = repository
    }

    func cachedDisplayName() -> String? {
        repository.getCachedDisplayName()
    }

    func cachedProfilePictureURL() -> String? {
        repository.getCachedProfilePictureURL()
    }

    func clearCache() {
        repository.clearUserCache()
    }

    func saveInitialUser(_ user: AuthenticatedUser) async throws {
        let existingData = try? await repository.getUserFromFirestore(userId: user.uid)

        try await repository.saveUserToFirestore(
            userId: user.uid,
            email: user.email,
            firstName: existingData?.firstName,
            lastName: existingData?.lastName,
            displayName: existingData?.displayName,
            age: existingData?.age,
            gender: existingData?.gender,
            weightKg: existingData?.weightKg,
            heightCm: existingData?.heightCm,
            locationCity: existingData?.locationCity,
            locationCountry: existingData?.locationCountry,
            locationRegion: existingData?.locationRegion,
            onboardingFirstClimbId: existingData?.onboardingFirstClimbId,
            joinedAt: existingData?.joinedAt ?? user.creationDate
        )
    }

    func displayName(userID: String) async -> String? {
        await repository.getDisplayName(userId: userID)
    }

    func profilePictureURL(userID: String) async -> String? {
        await repository.getProfilePictureURL(userId: userID)
    }
}
