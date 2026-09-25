import CryptoKit
import Foundation
import UIKit

/// Fetches and caches a climb's progress cut-out (`Climb.progressArtwork`).
///
/// The image lives in Storage beside the climb's other artwork and lands in the same disk cache
/// (`DiskAssetCache.climbImages`), keyed by its Storage path. Nothing is bundled and nothing is
/// fetched in bulk: a climb's cut-out is prefetched when its detail page opens (and for the
/// featured climb), and a live climb takes it from the cache, or fetches it on the spot.
protocol ClimbProgressImageRepository: Sendable {
    /// Makes sure the image is on disk, downloading it if it is not. Never decodes it.
    func prefetch(_ artwork: ClimbProgressArtwork) async

    /// The decoded image, from disk or downloaded, or nil when it cannot be had or does not
    /// match the catalog's description of it - in which case the caller keeps its fallback.
    func image(for artwork: ClimbProgressArtwork) async -> UIImage?
}

/// Moves one Storage object to a local file. Split out so the fetch and fallback paths are
/// testable without Firebase.
protocol ClimbStorageObjectDownloading: Sendable {
    func download(path: String, to fileURL: URL) async throws
}

final class StorageClimbProgressImageRepository: ClimbProgressImageRepository, @unchecked Sendable {
    static let shared = StorageClimbProgressImageRepository()

    private let cache: DiskAssetCache
    private let downloader: any ClimbStorageObjectDownloading
    private let inFlight = InFlightDownloads()

    init(
        cache: DiskAssetCache = .climbImages,
        downloader: any ClimbStorageObjectDownloading = FirebaseClimbStorageObjectDownloader()
    ) {
        self.cache = cache
        self.downloader = downloader
    }

    func prefetch(_ artwork: ClimbProgressArtwork) async {
        _ = await fileURL(for: artwork)
    }

    func image(for artwork: ClimbProgressArtwork) async -> UIImage? {
        guard let fileURL = await fileURL(for: artwork) else { return nil }
        guard let image = Self.decode(fileURL, as: artwork) else {
            // A cached file that no longer decodes to the catalog's canvas is not this artwork;
            // drop it so the next attempt downloads a fresh copy rather than failing forever.
            try? cache.remove(for: artwork.path)
            return nil
        }
        return image
    }

    /// The cached file, or a fresh download of it. Concurrent requests for the same path - a
    /// prefetch still running when the climb starts - share one download.
    private func fileURL(for artwork: ClimbProgressArtwork) async -> URL? {
        if let cachedURL = cache.fileURLIfPresent(for: artwork.path) {
            return cachedURL
        }
        return await inFlight.run(key: artwork.path) { [self] in
            if let cachedURL = cache.fileURLIfPresent(for: artwork.path) {
                return cachedURL
            }
            return await download(artwork)
        }
    }

    private func download(_ artwork: ClimbProgressArtwork) async -> URL? {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            try await downloader.download(path: artwork.path, to: temporaryURL)
        } catch {
            return nil
        }

        if let expected = artwork.sha256?.lowercased() {
            guard let data = try? Data(contentsOf: temporaryURL, options: .mappedIfSafe),
                  Self.sha256Hex(of: data) == expected else {
                return nil
            }
        }

        return try? cache.storeFile(at: temporaryURL, for: artwork.path)
    }

    /// Decodes and pre-renders the image off the main actor, and only accepts it at the canvas
    /// size the catalog's bounds were measured on - at any other size they no longer describe it.
    static func decode(_ fileURL: URL, as artwork: ClimbProgressArtwork) -> UIImage? {
        guard let image = UIImage(contentsOfFile: fileURL.path(percentEncoded: false)),
              let cgImage = image.cgImage,
              cgImage.width == artwork.canvasWidth,
              cgImage.height == artwork.canvasHeight else {
            return nil
        }
        return image.preparingForDisplay() ?? image
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// One running download per key; later callers await the first one's result.
private actor InFlightDownloads {
    private var tasks: [String: Task<URL?, Never>] = [:]

    func run(key: String, _ operation: @escaping @Sendable () async -> URL?) async -> URL? {
        if let running = tasks[key] {
            return await running.value
        }
        let task = Task { await operation() }
        tasks[key] = task
        let result = await task.value
        tasks[key] = nil
        return result
    }
}
