import Foundation

/// Thrown in place of a Firestore operation that `FirestoreDiskGuard` refused because the
/// volume is at the floor. Classified as `ServerReadFailureClass.unreachable`: the server was
/// never asked, nothing is wrong with the data, and the condition clears on its own once the
/// phone has room again.
struct FirestoreLowDiskRefusal: LocalizedError, Equatable, Sendable {
    /// What `statfs` reported when the refusal was made, nil when the volume could not be asked.
    let availableBytes: Int64?

    var errorDescription: String? {
        let bytes = availableBytes.map(String.init) ?? "unknown"
        return "Firestore operation refused: the volume is at the low-disk floor (available bytes: \(bytes))."
    }
}
