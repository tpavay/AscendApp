import Foundation
import Testing
import UIKit

@testable import AscendApp

/// The fetch path for a climb's progress cut-out: disk cache first, Storage when it is missing,
/// and every way a download can go wrong resolving to "no cut-out" (the caller's photo-layout
/// fallback) rather than a broken or mismatched image.
struct ClimbProgressImageRepositoryTests {
    private static let climbID = "charminar"

    @Test("A miss downloads once, verifies, caches; the next request is served from disk")
    func missDownloadsThenHits() async throws {
        let (repository, downloader, cache) = try Self.makeRepository()
        defer { try? cache.clear() }
        let artwork = try Self.artwork()

        #expect(cache.fileURLIfPresent(for: artwork.path) == nil)
        let first = await repository.image(for: artwork)
        #expect(first != nil)
        #expect(downloader.downloadCount == 1)
        #expect(cache.fileURLIfPresent(for: artwork.path) != nil, "the verified download is kept in the climb-image cache")

        let second = await repository.image(for: artwork)
        #expect(second != nil)
        #expect(downloader.downloadCount == 1, "a cached cut-out is never fetched again")
    }

    @Test("Prefetch puts the file on disk so a later live climb needs no network")
    func prefetchWarmsTheCache() async throws {
        let (repository, downloader, cache) = try Self.makeRepository()
        defer { try? cache.clear() }
        let artwork = try Self.artwork()

        await repository.prefetch(artwork)
        #expect(downloader.downloadCount == 1)
        #expect(cache.fileURLIfPresent(for: artwork.path) != nil)

        downloader.failure = URLError(.notConnectedToInternet)
        #expect(await repository.image(for: artwork) != nil, "offline at the start line, the prefetched copy still draws")
        #expect(downloader.downloadCount == 1)
    }

    @Test("A download that fails leaves nothing cached and answers no cut-out")
    func failedDownloadFallsBack() async throws {
        let (repository, downloader, cache) = try Self.makeRepository()
        defer { try? cache.clear() }
        downloader.failure = URLError(.timedOut)
        let artwork = try Self.artwork()

        #expect(await repository.image(for: artwork) == nil)
        #expect(cache.fileURLIfPresent(for: artwork.path) == nil)

        downloader.failure = nil
        #expect(await repository.image(for: artwork) != nil, "the next attempt fetches afresh")
    }

    @Test("A download whose bytes do not match the catalog's SHA-256 is discarded, never cached")
    func checksumMismatchIsDiscarded() async throws {
        let (repository, _, cache) = try Self.makeRepository()
        defer { try? cache.clear() }
        let artwork = try Self.artwork(sha256: String(repeating: "0", count: 64))

        #expect(await repository.image(for: artwork) == nil)
        #expect(cache.fileURLIfPresent(for: artwork.path) == nil)
    }

    @Test("An image at a different size than the catalog measured is refused and evicted")
    func wrongCanvasSizeIsRefused() async throws {
        let (repository, _, cache) = try Self.makeRepository()
        defer { try? cache.clear() }
        let real = try Self.artwork()
        let mismatched = ClimbProgressArtwork(
            path: real.path,
            canvasWidth: real.canvasWidth + 1,
            canvasHeight: real.canvasHeight,
            visibleBoundsPixels: real.visibleBoundsPixels,
            progressTopY: real.progressTopY,
            progressBottomY: real.progressBottomY,
            sha256: real.sha256
        )

        #expect(await repository.image(for: mismatched) == nil)
        #expect(cache.fileURLIfPresent(for: real.path) == nil, "a file its bounds do not describe is not kept")
    }

    @Test("A prefetch still running when the climb starts shares its download")
    func concurrentRequestsShareOneDownload() async throws {
        let (repository, downloader, cache) = try Self.makeRepository()
        defer { try? cache.clear() }
        downloader.delay = .milliseconds(200)
        let artwork = try Self.artwork()

        async let prefetched: Void = repository.prefetch(artwork)
        async let image = repository.image(for: artwork)
        _ = await prefetched
        #expect(await image != nil)
        #expect(downloader.downloadCount == 1)
    }

    // MARK: - Fixtures

    private static func artwork(sha256: String? = nil) throws -> ClimbProgressArtwork {
        let catalog = try #require(BundledClimbCatalog.climbs.first { $0.id == climbID }?.progressArtwork)
        return ClimbProgressArtwork(
            path: catalog.path,
            canvasWidth: catalog.canvasWidth,
            canvasHeight: catalog.canvasHeight,
            visibleBoundsPixels: catalog.visibleBoundsPixels,
            progressTopY: catalog.progressTopY,
            progressBottomY: catalog.progressBottomY,
            sha256: sha256 ?? catalog.sha256
        )
    }

    private static func makeRepository() throws -> (StorageClimbProgressImageRepository, StubDownloader, DiskAssetCache) {
        let cache = DiskAssetCache(namespace: "ClimbProgressImageRepositoryTests-\(UUID().uuidString)", maxBytes: 64 * 1024 * 1024)
        let downloader = StubDownloader(source: FixtureClimbProgressImageRepository.fixtureURL(forClimbID: climbID))
        return (StorageClimbProgressImageRepository(cache: cache, downloader: downloader), downloader, cache)
    }

    /// Copies a fixture PNG into place the way a Storage download writes its file.
    private final class StubDownloader: ClimbStorageObjectDownloading, @unchecked Sendable {
        private let lock = NSLock()
        private let source: URL
        private var _downloadCount = 0
        private var _failure: (any Error)?
        private var _delay: Duration = .zero

        init(source: URL) {
            self.source = source
        }

        var downloadCount: Int { lock.withLock { _downloadCount } }
        var failure: (any Error)? {
            get { lock.withLock { _failure } }
            set { lock.withLock { _failure = newValue } }
        }
        var delay: Duration {
            get { lock.withLock { _delay } }
            set { lock.withLock { _delay = newValue } }
        }

        func download(path: String, to fileURL: URL) async throws {
            let (failure, delay) = lock.withLock {
                _downloadCount += 1
                return (_failure, _delay)
            }
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
            if let failure {
                throw failure
            }
            try FileManager.default.copyItem(at: source, to: fileURL)
        }
    }
}
