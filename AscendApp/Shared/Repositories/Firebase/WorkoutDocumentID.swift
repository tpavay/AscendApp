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
}
