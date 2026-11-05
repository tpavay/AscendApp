import Foundation
@preconcurrency import FirebaseFirestore

/// Reads the signed-out weekly board. A failure is an absent board, never an error a climber
/// sees: the screen is complete without it, and a sign-in screen is not where a network problem
/// should speak.
struct PublicWeeklyBoardRepository: Sendable {
    static let collection = "public_weekly_steps_top"
    static let documentID = "current"

    let fetch: @Sendable (_ now: Date) async -> PublicWeeklyBoard?

    static let live = PublicWeeklyBoardRepository { now in
        do {
            let snapshot = try await Firestore.firestore()
                .collection(collection)
                .document(documentID)
                .getServerDocument()
            guard let data = snapshot.data() else { return nil }
            return PublicWeeklyBoard.parse(data, now: now)
        } catch {
            return nil
        }
    }
}
