import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Sorts a failed sync attempt into the category the retry policy acts on.
///
/// The categories mirror the pinned Firestore SDK's own write classification (11.15.0,
/// `datastore.cc`) rather than a shorter guess: the SDK leaves `cancelled`, `unknown`,
/// `deadlineExceeded`, `resourceExhausted`, `internal`, `unavailable` and `unauthenticated` on its
/// write stream to retry, and rejects the batch for `invalidArgument`, `notFound`, `alreadyExists`,
/// `permissionDenied`, `failedPrecondition`, `outOfRange`, `unimplemented` and `dataLoss`.
///
/// A rejected batch is the only case Ascend must re-offer itself, because the SDK has stopped
/// carrying it. Everything the SDK still owns is left alone - re-enqueuing it would duplicate a
/// mutation that is still in flight.
enum WorkoutSyncFailureClassifier {
    static func category(
        for error: any Error,
        isConnected: Bool
    ) -> WorkoutSyncFailureCategory {
        if error is CancellationError { return .cancelled }

        if let sidecarError = error as? WorkoutHeartRateSidecarError {
            return sidecarError == .forbidden ? .refused : .transient
        }

        let nsError = error as NSError

        switch nsError.domain {
        case NSURLErrorDomain where nsError.code == NSURLErrorCancelled:
            return .cancelled
        case FirestoreErrorDomain:
            return firestoreCategory(for: nsError.code, isConnected: isConnected)
        case StorageErrorDomain:
            return storageCategory(for: nsError.code, isConnected: isConnected)
        default:
            return isConnected ? .transient : .offline
        }
    }

    /// `permissionDenied` is deliberately `refused`, never `malformed`.
    ///
    /// It is terminal to the SDK but ambiguous to Ascend: the incident behind this work proved a
    /// deployable rules defect produces the identical code to a genuine authorization denial, and
    /// no client-only classifier can tell them apart. So it earns the conjunctive count-plus-elapsed
    /// gate in `WorkoutSyncRetryPolicy` rather than an instant verdict, and it stays re-openable.
    ///
    /// `invalidArgument` and `outOfRange` are `malformed` because the request itself has to change
    /// before any attempt can succeed - re-offering identical bytes is pure waste.
    private static func firestoreCategory(for code: Int, isConnected: Bool) -> WorkoutSyncFailureCategory {
        switch code {
        case FirestoreErrorCode.permissionDenied.rawValue,
             FirestoreErrorCode.failedPrecondition.rawValue,
             FirestoreErrorCode.notFound.rawValue,
             FirestoreErrorCode.alreadyExists.rawValue:
            return .refused
        case FirestoreErrorCode.invalidArgument.rawValue,
             FirestoreErrorCode.outOfRange.rawValue,
             FirestoreErrorCode.unimplemented.rawValue,
             FirestoreErrorCode.dataLoss.rawValue:
            return .malformed
        case FirestoreErrorCode.unauthenticated.rawValue:
            return .authentication
        case FirestoreErrorCode.unavailable.rawValue:
            return isConnected ? .transient : .offline
        default:
            return .transient
        }
    }

    private static func storageCategory(for code: Int, isConnected: Bool) -> WorkoutSyncFailureCategory {
        switch code {
        case StorageErrorCode.unauthorized.rawValue:
            return .refused
        case StorageErrorCode.unauthenticated.rawValue:
            return .authentication
        default:
            return isConnected ? .transient : .offline
        }
    }
}
