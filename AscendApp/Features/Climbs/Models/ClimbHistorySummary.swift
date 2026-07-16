import Foundation

struct ClimbHistorySummary: Equatable {
    let climb: Climb
    let attemptsCount: Int
    let completionsCount: Int
    let failedAttemptsCount: Int
    let bestCompletionDurationSeconds: Int?
    let globalCompletionOrder: Int?
    let averageCompletionDurationSeconds: Int?
    let recentEntries: [ClimbHistoryEntry]

    static func empty(for climb: Climb) -> ClimbHistorySummary {
        ClimbHistorySummary(
            climb: climb,
            attemptsCount: 0,
            completionsCount: 0,
            failedAttemptsCount: 0,
            bestCompletionDurationSeconds: nil,
            globalCompletionOrder: nil,
            averageCompletionDurationSeconds: nil,
            recentEntries: []
        )
    }
}
