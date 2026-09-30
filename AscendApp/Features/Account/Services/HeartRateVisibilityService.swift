import Foundation
import SwiftData

/// The switch's server side. The choice is stored on the climber's own `profile_stats` document
/// beside the two aggregates it governs, and written with them in one transaction - there is no
/// moment where the switch reads off and another climber can still read a number.
///
/// That write deliberately bypasses the identity and activity publication and the
/// public-profile kill switch: hiding is a privacy retraction that must always work, even when
/// the name no longer validates or publishing is paused, and it only ever removes or restates
/// the owner's own aggregates. A climber with no published stats yet gets a full publication.
@MainActor
struct HeartRateVisibilityService: HeartRateVisibilityProviding {
    let userId: String
    let joinedAt: Date?
    let modelContext: ModelContext
    var repository: ProfileRepository = .shared

    func loadIsPublic() async throws -> Bool {
        try await repository.fetchHeartRatePublic(userId: userId)
    }

    func setIsPublic(_ isPublic: Bool) async throws {
        try ProfilePublicationError.requireConnection()
        do {
            let heartRate = try isPublic ? ownHeartRate() : nil
            let existed = try await repository.setHeartRateVisibility(
                userId: userId,
                isPublic: isPublic,
                heartRate: heartRate
            )
            guard !existed else { return }
            try await ProfilePublicationService.publish(
                modelContext: modelContext,
                userId: userId,
                joinedAt: joinedAt,
                heartRatePublic: isPublic,
                repository: repository
            )
        } catch {
            throw ProfilePublicationError.mappingLostConnection(error)
        }
    }

    private func ownHeartRate() throws -> ProfileHeartRateSummary? {
        let userId = userId
        let workouts = try modelContext.fetch(
            FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.ownerUserId == userId
                }
            )
        )
        return ProfileHeartRateSummary.derive(
            from: workouts.map { workout in
                ProfileHeartRateSummary.Climb(
                    durationSeconds: workout.duration,
                    averageBpm: workout.avgHeartRate,
                    maxBpm: workout.maxHeartRate
                )
            }
        )
    }
}
