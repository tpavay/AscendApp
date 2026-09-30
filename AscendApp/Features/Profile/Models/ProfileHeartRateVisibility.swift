import Foundation

/// A climber's "Show my heart rate on my profile" choice, stored as `heart_rate_public` on their
/// own `profile_stats` document so every device and every publication reads the same answer.
///
/// On by default: a climber who never touched the switch shows their heart rate. Off means other
/// climbers see no heart-rate number from them anywhere - the publisher removes both aggregates,
/// `firestore.rules` refuses a document that is hidden and still carries one, and the backfill
/// skips them. The climber's own numbers are derived on their device and never depend on it.
enum ProfileHeartRateVisibility {
    static let defaultIsPublic = true

    static func isPublic(stored: Any?) -> Bool {
        (stored as? Bool) ?? defaultIsPublic
    }
}
