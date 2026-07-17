import Foundation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

/// Server-backed email preferences for the signed-in user.
///
/// Reads come straight from the owner-readable preferences document; writes go
/// through the lifecycle callable so the server stays the only writer.
struct EmailPreferencesService: EmailPreferencesProviding {
    func loadLifecycleEmailsEnabled() async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw LifecycleEventRecorderError.signedOut
        }

        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("communication_preferences")
            .document("current")
            .getDocument()

        // No stored preference means the user has never opted out.
        guard let isEnabled = snapshot
            .data()?["lifecycleEmailsEnabled"] as? Bool else {
            return true
        }

        return isEnabled
    }

    func setLifecycleEmailsEnabled(_ isEnabled: Bool) async throws {
        try await LifecycleEventRecorder.shared.recordCommunicationPreferences(
            lifecycleEmailsEnabled: isEnabled
        )
    }
}
