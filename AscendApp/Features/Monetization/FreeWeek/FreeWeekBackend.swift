import Foundation
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseFunctions

/// Reads `users/{uid}/trial/free_week`, the one free-week document the rules let its owner read.
@MainActor
protocol FreeWeekRecordReading: AnyObject {
    /// The account's week, or `nil` when the server answered and there is no record.
    func readRecord(userID: String) async throws -> FreeWeekGrant?
}

/// Calls the authenticated `startFreeWeek` callable.
@MainActor
protocol FreeWeekGranting: AnyObject {
    func startFreeWeek() async throws -> FreeWeekGrantResponse
}

@MainActor
final class FirestoreFreeWeekRecordReader: FreeWeekRecordReading {
    func readRecord(userID: String) async throws -> FreeWeekGrant? {
        let snapshot = try await Firestore.firestore()
            .collection("users").document(userID)
            .collection("trial").document("free_week")
            .getServerDocument()
        guard snapshot.exists else { return nil }
        guard let grantedAt = (snapshot.get("grantedAt") as? Timestamp)?.dateValue(),
              let expiresAt = (snapshot.get("expiresAt") as? Timestamp)?.dateValue() else {
            // A record the app cannot read still proves a week was given. The server spends it the
            // same way, so the two agree that this account has no week left.
            return FreeWeekGrant(grantedAt: .distantPast, expiresAt: .distantPast)
        }

        return FreeWeekGrant(grantedAt: grantedAt, expiresAt: expiresAt)
    }
}

/// It takes no arguments on purpose: the account is the one Firebase Authentication verified and
/// the window is the server's clock, so nothing about the week comes from the device.
@MainActor
final class FunctionsFreeWeekGranter: FreeWeekGranting {
    private static let callableName = "startFreeWeek"

    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "us-central1")) {
        self.functions = functions
    }

    func startFreeWeek() async throws -> FreeWeekGrantResponse {
        let result = try await functions.httpsCallable(Self.callableName).call()
        return FreeWeekGrantResponse(payload: result.data as? [String: Any])
    }
}
