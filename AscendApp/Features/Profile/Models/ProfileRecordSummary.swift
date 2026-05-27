import Foundation

struct ProfileRecordSummary {
    struct PersonalRecord: Identifiable, Equatable {
        enum Kind: String {
            case mostSteps
            case longestClimb
            case fastestPace
        }

        let kind: Kind
        let label: String
        let valueText: String?
        let date: Date?

        var id: String { kind.rawValue }
    }

    let personalRecords: [PersonalRecord]
    let featuredBestEffort: RankedBestEffort?
}
