import Foundation
@preconcurrency import FirebaseFirestore

final class ModerationRepository: ModerationRepositoryProtocol, Sendable {
    static let shared = ModerationRepository()

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchBlockedClimbers(
        blockerUserId: String,
        source: BlockListReadSource
    ) async throws -> [BlockedClimber] {
        let snapshot = try await blockedCollection(blockerUserId: blockerUserId)
            .order(by: "createdAt", descending: true)
            .getDocuments(source: Self.firestoreSource(for: source))

        return snapshot.documents.compactMap { document in
            let data = document.data()
            guard let blockedUserId = data["blockedUid"] as? String,
                  blockedUserId == document.documentID,
                  let createdAt = data["createdAt"] as? Timestamp else {
                return nil
            }

            return BlockedClimber(
                userId: blockedUserId,
                createdAt: createdAt.dateValue()
            )
        }
    }

    /// Blocking is idempotent.
    ///
    /// The rules allow `create` only, so re-blocking a climber this device did
    /// not know about - blocked on another device, or hydrated from nothing - is
    /// denied even though the block already exists. Telling the user the block
    /// didn't save would be a lie, so an existing block counts as success.
    func block(blockerUserId: String, blockedUserId: String) async throws {
        let document = blockedCollection(blockerUserId: blockerUserId)
            .document(blockedUserId)

        do {
            try await document.setData(
                Self.blockPayload(blockedUserId: blockedUserId)
            )
        } catch {
            guard Self.isPermissionDenied(error),
                  await Self.documentExistsOnServer(document) else {
                throw error
            }
        }
    }

    func unblock(blockerUserId: String, blockedUserId: String) async throws {
        try await blockedCollection(blockerUserId: blockerUserId)
            .document(blockedUserId)
            .delete()
    }

    func submitReport(
        reporterUserId: String,
        reportedUserId: String,
        reason: ModerationReportReason,
        source: ModerationSource
    ) async throws {
        let reportReference = db.collection("moderation_reports").document()
        let rateLimitReference = db.collection("userRateLimits")
            .document(reporterUserId)
        let batch = db.batch()
        batch.setData(
            Self.reportPayload(
                reporterUserId: reporterUserId,
                reportedUserId: reportedUserId,
                reason: reason,
                source: source
            ),
            forDocument: reportReference
        )
        batch.setData(
            Self.reportRateLimitPayload(reportId: reportReference.documentID),
            forDocument: rateLimitReference,
            merge: true
        )
        try await batch.commit()
    }

    static func blockPayload(blockedUserId: String) -> [String: Any] {
        [
            "blockedUid": blockedUserId,
            "createdAt": FieldValue.serverTimestamp()
        ]
    }

    static func reportPayload(
        reporterUserId: String,
        reportedUserId: String,
        reason: ModerationReportReason,
        source: ModerationSource
    ) -> [String: Any] {
        [
            "reportedUserId": reportedUserId,
            "reporterUserId": reporterUserId,
            "reason": reason.rawValue,
            "source": source.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ]
    }

    static func reportRateLimitPayload(reportId: String) -> [String: Any] {
        [
            "lastModerationReport": FieldValue.serverTimestamp(),
            "lastModerationReportId": reportId
        ]
    }

    private static func firestoreSource(
        for source: BlockListReadSource
    ) -> FirestoreSource {
        switch source {
        case .server: .server
        case .cache: .cache
        }
    }

    private static func isPermissionDenied(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == FirestoreErrorDomain &&
            error.code == FirestoreErrorCode.permissionDenied.rawValue
    }

    private static func documentExistsOnServer(
        _ document: DocumentReference
    ) async -> Bool {
        do {
            return try await document.getDocument(source: .server).exists
        } catch {
            return false
        }
    }

    private func blockedCollection(blockerUserId: String) -> CollectionReference {
        db.collection("users")
            .document(blockerUserId)
            .collection("blocked")
    }
}
