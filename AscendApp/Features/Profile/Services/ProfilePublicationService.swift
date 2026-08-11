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
        // Killed: nothing local depends on the mirror having been written, so the next bootstrap
        // after the flag returns republishes from the same local state.
        guard RemoteFeatureGate.allows(
            .publicProfilePublishing,
            path: "ProfilePublicationService.publishCurrentUserProfile",
            store: featureFlags
        ) else {
            return
        }

        do {
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
            let achievementCounts = ProfileAchievementCounts(records: achievements)
            let snapshot = ProfileSnapshotBuilder.makeOwnSnapshot(
                demographics: identity.demographicsSnapshot,
                workouts: workouts,
                climbAttempts: attempts,
                bestEffortCacheEntries: cacheEntries,
                achievements: achievementCounts,
                achievementRecords: achievements,
                standings: [],
                climbs: climbs,
                fitnessLevel: SettingsManager.shared.fitnessLevel
            )

            try await repository.upsertPublicIdentity(identity)
            try await repository.upsertStats(userId: userId, stats: snapshot.stats)
            try await repository.replaceWorkoutSummaries(
                userId: userId,
                summaries: Array(snapshot.activityWorkouts.prefix(60))
            )
        } catch {
            debugLog("Profile publication failed: \(error)")
        }
    }
}
