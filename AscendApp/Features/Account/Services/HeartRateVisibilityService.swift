import Foundation
import SwiftData

/// The switch's server side. The choice is stored on the climber's own `profile_stats` document
/// and applied by a full profile publication carrying it, so turning it off removes the
/// published heart rate in the same transaction that records the choice - there is no moment
/// where the switch reads off and another climber can still read a number.
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
}
