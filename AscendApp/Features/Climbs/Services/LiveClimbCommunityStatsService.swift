import Foundation
@preconcurrency import FirebaseFirestore

struct LiveClimbCommunitySummary: Equatable, Sendable {
    let uniqueCompletedUserCount: Int
    let updatedAt: Date?

    init(uniqueCompletedUserCount: Int, updatedAt: Date?) {
        self.uniqueCompletedUserCount = max(uniqueCompletedUserCount, 0)
        self.updatedAt = updatedAt
    }

    static let empty = LiveClimbCommunitySummary(
        uniqueCompletedUserCount: 0,
        updatedAt: nil
    )
}

protocol LiveClimbCommunityStatsServicing: Sendable {
    func fetchSummary() async throws -> LiveClimbCommunitySummary
}

final class FirestoreLiveClimbCommunityStatsService: LiveClimbCommunityStatsServicing, @unchecked Sendable {
    static let shared = FirestoreLiveClimbCommunityStatsService()

    private let db = Firestore.firestore()

    private init() {}

    func fetchSummary() async throws -> LiveClimbCommunitySummary {
        let snapshot = try await db
            .collection("live_climb_community_stats")
            .document("global")
            .getDocument(source: .server)

        guard let data = snapshot.data() else {
            return .empty
        }

        return LiveClimbCommunitySummary(
            uniqueCompletedUserCount: intValue(for: "uniqueCompletedUserCount", in: data) ?? 0,
            updatedAt: timestampValue(for: "updatedAt", in: data)
        )
    }

    private func intValue(for key: String, in data: [String: Any]) -> Int? {
        if let value = data[key] as? Int {
            return value
        }

        if let value = data[key] as? NSNumber {
            return value.intValue
        }

        return nil
    }

    private func timestampValue(for key: String, in data: [String: Any]) -> Date? {
        (data[key] as? Timestamp)?.dateValue()
    }
}
