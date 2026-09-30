import Foundation
@preconcurrency import FirebaseFirestore

/// The climbers someone filters Ascend Mountain's race down to, kept with their account so every
/// climb after - on any phone - starts with the same choice. Private like the block list: one
/// document per chosen climber under `users/{uid}/race_filter`, read only by its owner, and nobody
/// is told they were chosen.
protocol MountainRaceFilterRepository: Sendable {
    func fetchChosen(userId: String) async throws -> [String]

    /// Makes the stored choice `chosen`: adds the climbers it lacks and removes the ones it no
    /// longer holds.
    func save(userId: String, chosen: [String]) async throws
}

final class FirestoreMountainRaceFilterRepository: MountainRaceFilterRepository, Sendable {
    static let shared = FirestoreMountainRaceFilterRepository()

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchChosen(userId: String) async throws -> [String] {
        try await chosenOnServer(userId: userId)
    }

    /// Written as the difference from the server's copy, because a choice can only be created or
    /// deleted: re-creating one another phone already stored would be refused.
    func save(userId: String, chosen: [String]) async throws {
        let stored = Set(try await chosenOnServer(userId: userId))
        let wanted = Set(chosen)
        let batch = db.batch()
        for climberId in wanted.subtracting(stored) {
            batch.setData(Self.payload(climberId: climberId), forDocument: collection(userId: userId).document(climberId))
        }
        for climberId in stored.subtracting(wanted) {
            batch.deleteDocument(collection(userId: userId).document(climberId))
        }
        try await batch.commit()
    }

    static func payload(climberId: String) -> [String: Any] {
        [
            "climberUid": climberId,
            "createdAt": FieldValue.serverTimestamp()
        ]
    }

    private func chosenOnServer(userId: String) async throws -> [String] {
        let snapshot = try await collection(userId: userId)
            .order(by: "createdAt")
            .getDocuments(source: .server)
        return snapshot.documents.compactMap { document in
            guard let climberId = document.data()["climberUid"] as? String,
                  climberId == document.documentID else { return nil }
            return climberId
        }
    }

    private func collection(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("race_filter")
    }
}
