import FirebaseStorage
import Foundation

/// Downloads a climb-imagery object from the environment's Storage bucket, the same way
/// `FirebaseClimbImageRepository` fetches hero, card and thumb art.
struct FirebaseClimbStorageObjectDownloader: ClimbStorageObjectDownloading {
    func download(path: String, to fileURL: URL) async throws {
        let reference = Storage.storage().reference(withPath: path)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.write(toFile: fileURL) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
