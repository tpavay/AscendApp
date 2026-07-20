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
    static func aliasStrings(for workoutID: UUID) -> [String] {
        let canonical = canonicalString(for: workoutID)
        return [canonical.lowercased()].filter { $0 != canonical }
    }
}
