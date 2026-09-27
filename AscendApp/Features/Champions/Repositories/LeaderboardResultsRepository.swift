import Foundation
@preconcurrency import FirebaseFirestore

/// Reads the frozen results of closed Steps boards.
///
/// Both collections are server-written and paid-readable (`firestore.rules`); the client
/// never writes here. `docs/champion-recognition.md` owns the document shapes.
protocol LeaderboardResultsReading: Sendable {
    func fetchResult(timeFrame: LeaderboardTimeFrame, periodKey: String) async throws -> LeaderboardResult?
    func fetchPlacings(resultID: String, limit: Int) async throws -> [LeaderboardPlacing]
    func fetchChampionPlacings(resultID: String) async throws -> [LeaderboardPlacing]
    func fetchPlacings(resultID: String, userIds: [String]) async throws -> [LeaderboardPlacing]
}

final class LeaderboardResultsRepository: LeaderboardResultsReading, Sendable {
    static let shared = LeaderboardResultsRepository()

    static let resultsCollection = "leaderboard_results"
    static let placingsCollection = "placings"

    private init() {}

    /// Resolved on use rather than at construction, so a test that never reads Firestore
    /// never needs a configured Firebase app.
    private var db: Firestore {
        Firestore.firestore()
    }

    func fetchResult(timeFrame: LeaderboardTimeFrame, periodKey: String) async throws -> LeaderboardResult? {
        let snapshot = try await db.collection(Self.resultsCollection)
            .document(LeaderboardResult.documentID(timeFrame: timeFrame, periodKey: periodKey))
            .getDocument()
        guard let data = snapshot.data() else { return nil }
        return LeaderboardResultParser.result(from: data)
    }

    func fetchPlacings(resultID: String, limit: Int) async throws -> [LeaderboardPlacing] {
        let snapshot = try await placings(resultID: resultID)
            .order(by: "rank")
            .limit(to: max(limit, 0))
            .getDocuments()
        return LeaderboardResultParser.placings(from: snapshot.documents.map { $0.data() })
    }

    func fetchChampionPlacings(resultID: String) async throws -> [LeaderboardPlacing] {
        let snapshot = try await placings(resultID: resultID)
            .whereField("rank", isEqualTo: 1)
            .getDocuments()
        return LeaderboardResultParser.placings(from: snapshot.documents.map { $0.data() })
    }

    func fetchPlacings(resultID: String, userIds: [String]) async throws -> [LeaderboardPlacing] {
        let unique = Array(Set(userIds)).sorted()
        guard !unique.isEmpty else { return [] }

        let collection = placings(resultID: resultID)
        let found = try await withThrowingTaskGroup(of: LeaderboardPlacing?.self) { group in
            for userId in unique {
                group.addTask {
                    let data = try await collection.document(userId).getDocument().data()
                    return data.flatMap(LeaderboardResultParser.placing(from:))
                }
            }
            var found: [LeaderboardPlacing] = []
            for try await placing in group {
                if let placing { found.append(placing) }
            }
            return found
        }
        return found.sorted {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            return $0.userId < $1.userId
        }
    }

    private func placings(resultID: String) -> CollectionReference {
        db.collection(Self.resultsCollection)
            .document(resultID)
            .collection(Self.placingsCollection)
    }
}

/// Parses result and placing documents. Pure, so the shapes are testable without Firestore.
enum LeaderboardResultParser {
    static func result(from data: [String: Any]) -> LeaderboardResult? {
        guard let rawTimeFrame = data["timeFrame"] as? String,
              let timeFrame = LeaderboardTimeFrame(rawValue: rawTimeFrame),
              ChampionTitle(timeFrame: timeFrame) != nil,
              let periodKey = data["periodKey"] as? String,
              let startAt = date(data["periodStartAt"]),
              let endAt = date(data["periodEndAt"]) else {
            return nil
        }

        let mostClimbs: LeaderboardResult.MostClimbs? = (data["mostClimbs"] as? [String: Any]).flatMap {
            guard let count = int($0["count"]), count > 0 else { return nil }
            return LeaderboardResult.MostClimbs(
                count: count,
                userIds: strings($0["userIds"])
            )
        }
        let communityData = data["community"] as? [String: Any] ?? [:]

        return LeaderboardResult(
            period: LeaderboardPeriod(
                timeFrame: timeFrame,
                key: periodKey,
                startAt: startAt,
                endAt: endAt
            ),
            climberCount: max(int(data["climberCount"]) ?? 0, 0),
            championUserIds: strings(data["championUserIds"]),
            podiumUserIds: strings(data["podiumUserIds"]),
            mostClimbs: mostClimbs,
            community: LeaderboardResult.Community(
                climbers: max(int(communityData["climbers"]) ?? 0, 0),
                climbs: max(int(communityData["climbs"]) ?? 0, 0),
                steps: max(int(communityData["steps"]) ?? 0, 0),
                floors: max(int(communityData["floors"]) ?? 0, 0)
            )
        )
    }

    static func placings(from documents: [[String: Any]]) -> [LeaderboardPlacing] {
        documents
            .compactMap(placing(from:))
            .sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                return $0.userId < $1.userId
            }
    }

    /// A placing carries the same validated identity fields a `leaderboard_stats` row does,
    /// and is read under the same rules: an unpublished or deleted identity renders as the
    /// anonymous climber rather than whatever name the row happens to hold.
    static func placing(from data: [String: Any]) -> LeaderboardPlacing? {
        guard let userId = data["userId"] as? String,
              !userId.isEmpty,
              let rank = int(data["rank"]),
              rank >= 1 else {
            return nil
        }

        let identityState = data["identityState"] as? String
        let policyVersion = int(data["identityPolicyVersion"])
        let isPublished = identityState == "published" &&
            policyVersion == PublicClimberIdentity.policyVersion &&
            date(data["identityChangedAt"]) != nil
        let isSynthetic = data["isSynthetic"] as? Bool ?? false

        let identity: UnresolvedUserIdentity
        if isPublished || isSynthetic {
            identity = UnresolvedUserIdentity(
                displayName: data["displayName"] as? String ?? "",
                photoURL: (data["photoURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
                isSynthetic: isSynthetic
            )
        } else {
            identity = UnresolvedUserIdentity(
                displayName: PublicClimberIdentity.anonymousDisplayName,
                photoURL: nil
            )
        }

        return LeaderboardPlacing(
            userId: userId,
            unresolvedIdentity: identity,
            rank: rank,
            totalSteps: max(int(data["totalSteps"]) ?? 0, 0),
            totalWorkouts: max(int(data["totalWorkouts"]) ?? 0, 0)
        )
    }

    private static func strings(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: value
        case let value as Int64: Int(value)
        case let value as Double: value.isFinite ? Int(value) : nil
        case let value as NSNumber: value.intValue
        default: nil
        }
    }

    private static func date(_ value: Any?) -> Date? {
        switch value {
        case let timestamp as Timestamp: timestamp.dateValue()
        case let date as Date: date
        default: nil
        }
    }
}
