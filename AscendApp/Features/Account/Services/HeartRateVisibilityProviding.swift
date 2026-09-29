import Foundation

/// Reads and records the climber's "Show my heart rate on my profile" choice.
@MainActor
protocol HeartRateVisibilityProviding {
    /// The stored choice; a climber who never chose shows their heart rate.
    func loadIsPublic() async throws -> Bool

    /// Records the choice and applies it to the published heart rate in the same write.
    func setIsPublic(_ isPublic: Bool) async throws
}
