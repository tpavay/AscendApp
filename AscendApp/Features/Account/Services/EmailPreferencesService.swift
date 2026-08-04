import Foundation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

/// Server-backed email consent for the signed-in user.
///
/// Reads come straight from the owner-readable preferences document; writes go
/// through the lifecycle callable so the server stays the only writer and the
/// only source of the decision timestamp.
struct EmailPreferencesService: EmailPreferencesProviding {
    func loadConsent() async throws -> LifecycleEmailConsent {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw LifecycleEventRecorderError.signedOut
        }

        let snapshot = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("communication_preferences")
            .document("current")
            .getDocument()

        // An absent flag is an unanswered question, not a yes.
        return LifecycleEmailConsent(
            storedFlag: snapshot.data()?["lifecycleEmailsEnabled"] as? Bool
        )
    }

    func recordConsent(
        isGranted: Bool,
        source: LifecycleEmailConsentSource
    ) async throws {
        try await LifecycleEventRecorder.shared.recordCommunicationPreferences(
            lifecycleEmailsEnabled: isGranted,
            lifecycleEmailsSource: source
        )
    }
}
