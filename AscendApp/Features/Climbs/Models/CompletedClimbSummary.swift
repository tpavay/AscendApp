import Foundation

struct CompletedClimbSummary: Identifiable, Equatable {
    let climb: Climb
    let completedAt: Date
    let completionsCount: Int
    let bestCompletionDurationSeconds: Int?
    let collectionCount: Int
    let totalClimbs: Int
    let collectionOrder: Int?

    var id: String { climb.id }

    var collectionProgressText: String {
        "\(collectionCount.formatted()) / \(totalClimbs.formatted())"
    }
}
