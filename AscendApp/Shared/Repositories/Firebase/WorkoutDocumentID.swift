import Foundation

enum WorkoutDocumentID {
    static func canonicalString(for workoutID: UUID) -> String {
        workoutID.uuidString.uppercased()
    }

    static func canonicalString(from rawValue: String) -> String? {
        UUID(uuidString: rawValue).map(canonicalString(for:))
    }

    static func isCanonical(_ rawValue: String) -> Bool {
        canonicalString(from: rawValue) == rawValue
    }

    /// Legacy non-canonical document-id spellings the same workout may still exist under.
    ///
    /// Deprecated: this only ever matches dev/staging fixture documents. Remove it, and the
    /// alias delete in `WorkoutRemoteRepository.deleteWorkout`, by 2026-10-01 once
    /// `scripts/cleanup-case-variant-workout-ids.mjs` has been applied in both dev and staging.
    static func aliasStrings(for workoutID: UUID) -> [String] {
        let canonical = canonicalString(for: workoutID)
        return [canonical.lowercased()].filter { $0 != canonical }
    }
}
