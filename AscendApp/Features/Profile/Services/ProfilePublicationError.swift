import Foundation
import FirebaseFirestore

/// Failures that stop a profile edit from reaching both the private record and
/// the public mirror.
enum ProfilePublicationError: LocalizedError {
    case requiresConnection

    var errorDescription: String? {
        switch self {
        case .requiresConnection:
            return "Get back online to save this. Your name and photo publish to the leaderboard together."
        }
    }

    /// Fails fast when the app-wide connectivity source of truth says there is
    /// no connection.
    @MainActor
    static func requireConnection() throws {
        guard NetworkConnectivityService.shared.isConnected else {
            throw ProfilePublicationError.requiresConnection
        }
    }

    /// Reports a transport failure with the same honest message rather than a
    /// raw Firestore code.
    static func mappingLostConnection(_ error: Error) -> Error {
        if error is ProfilePublicationError {
            return error
        }

        let nsError = error as NSError
        guard nsError.domain == FirestoreErrorDomain,
              nsError.code == FirestoreErrorCode.unavailable.rawValue else {
            return error
        }
        return ProfilePublicationError.requiresConnection
    }
}
