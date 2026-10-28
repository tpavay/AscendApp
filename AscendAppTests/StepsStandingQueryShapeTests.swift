import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// The Totals stickers count the climbers ahead of you and the whole field with a range filter on
/// steps. Firestore serves that only from a composite index whose direction matches the query's
/// order, and the project declares the board's descending one; an unordered range filter needs an
/// ascending index that does not exist, fails with FAILED_PRECONDITION, and hides every rank
/// sticker. The emulator does not enforce indexes, so the shape is pinned here.
struct StepsStandingQueryShapeTests {
    private struct IndexFile: Decodable {
        struct Index: Decodable {
            struct Field: Decodable {
                let fieldPath: String
                let order: String?
            }

            let collectionGroup: String
            let fields: [Field]
        }

        let indexes: [Index]
    }

    @Test
    func theStandingCountsAreOrderedByStepsDescending() {
        let period = LeaderboardTimeFrame.weekly.currentPeriod()
        let query = LeaderboardRepository.shared.stepsBoardQuery(timeFrame: .weekly, period: period, above: 4_200)
        let expected = Firestore.firestore().collection("leaderboard_stats")
            .whereField("timeFrame", isEqualTo: LeaderboardTimeFrame.weekly.rawValue)
            .whereField("periodStartAt", isEqualTo: Timestamp(date: period.startAt))
            .whereField("totalSteps", isGreaterThan: 4_200)
            .order(by: "totalSteps", descending: true)
        #expect(query == expected)
    }

    /// `firestore.indexes.json` is the deployed index contract the counts above depend on.
    @Test
    func theDeployedIndexesServeTheStandingCounts() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "firestore.indexes.json")
        let file = try JSONDecoder().decode(IndexFile.self, from: Data(contentsOf: url))
        let shapes = file.indexes
            .filter { $0.collectionGroup == "leaderboard_stats" }
            .map { $0.fields.map { "\($0.fieldPath) \($0.order ?? "")" } }
        #expect(shapes.contains(["timeFrame ASCENDING", "periodStartAt ASCENDING", "totalSteps DESCENDING"]))
    }
}
