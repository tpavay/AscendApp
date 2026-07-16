import Foundation

enum WorkoutImportAnalyticsScreen {
    static func sheet(candidateCount: Int) -> TelemetryScreen {
        TelemetryScreen(
            name: "workout_import_sheet",
            screenClass: "WorkoutImportSheet",
            parameters: [
                "candidate_count_bucket": .string(candidateCountBucket(for: candidateCount))
            ]
        )
    }

    private static func candidateCountBucket(for count: Int) -> String {
        switch count {
        case ..<1:
            return "zero"
        case 1:
            return "one"
        case 2...5:
            return "2_5"
        case 6...10:
            return "6_10"
        default:
            return "11_plus"
        }
    }
}
