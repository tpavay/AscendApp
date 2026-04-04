import FirebaseStorage
import Foundation

final class FirebaseClimbImageRepository: ClimbImageRepository, @unchecked Sendable {
    static let shared = FirebaseClimbImageRepository()

    private let cache: DiskAssetCache
    private let storage: Storage

    init(
        cache: DiskAssetCache = .climbImages,
        storage: Storage = .storage()
    ) {
        self.cache = cache
        self.storage = storage
    }

    func resolveImageURL(for climb: Climb, variant: ClimbImageVariant) async -> URL? {
        let remotePaths = candidateRemotePaths(for: climb, variant: variant)

        for remotePath in remotePaths {
            let cacheKey = "climb-images/\(remotePath)"
            if let cachedURL = cache.fileURLIfPresent(for: cacheKey) {
                return cachedURL
            }

            do {
                let downloadedURL = try await downloadImage(at: remotePath, cacheKey: cacheKey)
                return downloadedURL
            } catch {
                continue
            }
        }

        return nil
    }

    private func candidateRemotePaths(for climb: Climb, variant: ClimbImageVariant) -> [String] {
        [
            "\(climb.id)/v\(climb.imageSetVersion)/\(variant.rawValue).heic",
            "\(climb.id)/\(variant.rawValue).heic"
        ]
    }

    private func downloadImage(at remotePath: String, cacheKey: String) async throws -> URL {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("heic")

        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let storageReference = storage.reference(withPath: "climb-images/\(remotePath)")
        try await write(reference: storageReference, to: temporaryURL)
        return try cache.storeFile(at: temporaryURL, for: cacheKey)
    }

    private func write(reference: StorageReference, to fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.write(toFile: fileURL) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }
}
