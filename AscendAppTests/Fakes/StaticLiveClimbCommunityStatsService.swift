import Foundation
@testable import AscendApp

/// A community summary that answers from memory, keeping a hosted globe off Firestore.
actor StaticLiveClimbCommunityStatsService: LiveClimbCommunityStatsServicing {
    private let summary: LiveClimbCommunitySummary
    private(set) var fetchCount = 0

    init(summary: LiveClimbCommunitySummary = .empty) {
        self.summary = summary
    }

    func fetchSummary() async throws -> LiveClimbCommunitySummary {
        fetchCount += 1
        return summary
    }
}
