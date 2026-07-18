import Foundation
@preconcurrency import FirebaseFirestore

/// Reads the server-derived `users/{uid}/landmarkResults` projection. Decodes
/// each document independently so one malformed row costs only that record,
/// never the whole set (same resilience as `WorkoutRemoteRepository`).
final class FirestoreClimbCompletionRemoteRepository:
    ClimbCompletionRemoteRepositoryProtocol, @unchecked Sendable {
    static let shared = FirestoreClimbCompletionRemoteRepository()

    private let db = Firestore.firestore()

    private init() {}

    func fetchLandmarkResults(userId: String) async throws -> [RemoteLandmarkResult] {
        let snapshot = try await db
            .collection("users")
            .document(userId)
            .collection("landmarkResults")
            .getDocuments()
        return snapshot.documents.compactMap {
            Self.decode(documentID: $0.documentID, data: $0.data())
        }
    }

    /// Decodes one projection document. Kept static and pure so the decode is
    /// testable without a live backend. A document that is not a completed
    /// landmark, or is missing its completion timestamps, is skipped.
    static func decode(documentID: String, data: [String: Any]) -> RemoteLandmarkResult? {
        guard boolValue(data["completed"]) == true else { return nil }

        let climbId = (data["climbId"] as? String) ?? documentID
        guard !climbId.isEmpty else { return nil }

        let firstCompletedAt = dateValue(data["firstCompletedAt"])
            ?? dateValue(data["latestCompletedAt"])
        let latestCompletedAt = dateValue(data["latestCompletedAt"])
            ?? firstCompletedAt
        guard let firstCompletedAt, let latestCompletedAt else { return nil }

        return RemoteLandmarkResult(
            climbId: climbId,
            completed: true,
            firstCompletedAt: firstCompletedAt,
            latestCompletedAt: latestCompletedAt,
            attemptCount: intValue(data["attemptCount"]) ?? 1,
            bestWorkoutId: (data["bestWorkoutId"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            bestElapsedSeconds: intValue(data["bestElapsedSeconds"])
        )
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = value as? Date {
            return date
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return nil
    }
}
