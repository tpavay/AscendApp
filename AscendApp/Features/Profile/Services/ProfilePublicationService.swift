import Foundation
import SwiftData

@MainActor
enum ProfilePublicationService {
    static func publishCurrentUserProfile(
        modelContext: ModelContext,
        userId: String,
        joinedAt: Date?,
        repository: ProfileRepository = .shared,
        featureFlags: RemoteFeatureFlagStore = .shared
    ) async {
        do {
            try await publish(
                modelContext: modelContext,
                userId: userId,
                joinedAt: joinedAt,
                repository: repository,
                featureFlags: featureFlags
            )
        } catch {
            debugLog("Profile publication failed: \(error)")
        }
    }

    /// The same publication, reporting failure instead of logging it - for a caller whose
    /// control has to say whether the write landed. `heartRatePublic` records the climber's
    /// "Show my heart rate on my profile" choice in the same write that applies it; omitted,
    /// the stored choice is kept.
    static func publish(
        modelContext: ModelContext,
        userId: String,
        joinedAt: Date?,
        heartRatePublic: Bool? = nil,
        repository: ProfileRepository = .shared,
        featureFlags: RemoteFeatureFlagStore = .shared
    ) async throws {
        // Killed: nothing local depends on the mirror having been written, so the next bootstrap
        // after the flag returns republishes from the same local state.
        guard RemoteFeatureGate.allows(
            .publicProfilePublishing,
            path: "ProfilePublicationService.publishCurrentUserProfile",
            store: featureFlags
        ) else {
            throw ProfilePublicationError.publishingPaused
        }

        let storedProfile = try await UserDataRepository.shared.getUserFromFirestore(
            userId: userId
        )
        let storedPhotoURL = storedProfile.profilePictureURL.flatMap(URL.init(string:))
        let publicIdentity = PublicClimberIdentity.resolve(
            userId: userId,
            storedDisplayName: storedProfile.resolvedDisplayName,
            storedPhotoURL: storedPhotoURL
        )
        let displayName = try DisplayNamePolicy.validated(publicIdentity.displayName)
        let identity = ProfileUserIdentity(
            userId: userId,
            displayName: displayName,
            photoURL: publicIdentity.photoURL,
            age: storedProfile.age,
            gender: storedProfile.gender.flatMap(ProfileGender.init(rawValue:)),
            weightKg: storedProfile.weightKg,
            heightCm: storedProfile.heightCm,
            locationCity: storedProfile.locationCity,
            locationCountryCode: storedProfile.locationCountry,
            locationRegionCode: storedProfile.locationRegion,
            joinedAt: storedProfile.joinedAt ?? joinedAt
        )
        let workouts = try modelContext.fetch(
            FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.ownerUserId == userId
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )
        let attempts = try modelContext.fetch(
            FetchDescriptor<ClimbAttempt>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        )
        let cacheEntries = try modelContext.fetch(
            FetchDescriptor<BestEffortCacheEntry>(
                sortBy: [SortDescriptor(\.sortKey)]
            )
        )
        let climbs = (try? ClimbService.shared.loadAllClimbs()) ?? []
        let achievements = (try? await repository.fetchAchievements(userId: userId)) ?? []
        let snapshot = ProfileSnapshotBuilder.makeOwnSnapshot(
            demographics: identity.demographicsSnapshot,
            workouts: workouts,
            climbAttempts: attempts,
            bestEffortCacheEntries: cacheEntries,
            achievements: ProfileAchievementLadder(records: achievements),
            standings: [],
            climbs: climbs,
            fitnessLevel: SettingsManager.shared.fitnessLevel
        )

        try await repository.upsertPublicIdentity(identity)
        try await repository.upsertStats(
            userId: userId,
            stats: snapshot.stats,
            heartRatePublic: heartRatePublic
        )
        try await repository.replaceWorkoutSummaries(
            userId: userId,
            summaries: Array(snapshot.activityWorkouts.prefix(60))
        )
    }
}
