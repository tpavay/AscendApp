import Foundation
import SwiftData

@MainActor
enum ProfilePublicationService {
    static func publishCurrentUserProfile(
        modelContext: ModelContext,
        userId: String,
        displayName: String,
        photoURL: URL?,
        joinedAt: Date?,
        repository: ProfileRepository = .shared
    ) async {
        do {
            let storedProfile = try? await UserDataRepository.shared.getUserFromFirestore(userId: userId)
            let identity = ProfileUserIdentity(
                userId: userId,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Climber" : displayName,
                photoURL: photoURL,
                age: storedProfile?.age,
                gender: storedProfile?.gender.flatMap(ProfileGender.init(rawValue:)),
                weightKg: storedProfile?.weightKg,
                locationCountryCode: storedProfile?.locationCountry,
                locationRegionCode: storedProfile?.locationRegion,
                joinedAt: storedProfile?.joinedAt ?? joinedAt
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
            let climbs = (try? ClimbService.shared.loadClimbs()) ?? []
            let achievements = (try? await repository.fetchAchievements(userId: userId)) ?? []
            let achievementCounts = ProfileAchievementCounts(records: achievements)
            let snapshot = ProfileSnapshotBuilder.makeOwnSnapshot(
                identity: identity,
                workouts: workouts,
                climbAttempts: attempts,
                bestEffortCacheEntries: cacheEntries,
                achievements: achievementCounts,
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
            print("Profile publication failed: \(error)")
        }
    }
}
