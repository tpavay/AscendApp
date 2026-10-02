import FirebaseCore
import Foundation

/// Where the unlock catalogue comes from: the copy hosted beside the climb catalogue, the last
/// one this device fetched, or the one bundled with the build - in that order of freshness.
protocol UnlockCatalogRepository: Sendable {
    /// The catalogue to start from without waiting on the network.
    func loadInitialCatalog() -> UnlockCatalog
    /// The hosted catalogue, kept for the next launch.
    func refreshCatalog() async throws -> UnlockCatalog
}

struct HostedUnlockCatalogRepository: UnlockCatalogRepository {
    private let cache: DiskAssetCache
    private let session: URLSession
    private let bundle: Bundle
    static let path = "unlocks/catalog.json"
    static let bundledResource = "unlock-catalog"

    init(cache: DiskAssetCache = .climbCatalog, session: URLSession = .shared, bundle: Bundle = .main) {
        self.cache = cache
        self.session = session
        self.bundle = bundle
    }

    func loadInitialCatalog() -> UnlockCatalog {
        if let data = try? cache.data(for: Self.path), let cached = try? JSONDecoder().decode(UnlockCatalog.self, from: data) {
            return cached
        }
        return Self.bundledCatalog(in: bundle)
    }

    static func bundledCatalog(in bundle: Bundle = .main) -> UnlockCatalog {
        guard let url = bundle.url(forResource: bundledResource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(UnlockCatalog.self, from: data) else { return .empty }
        return catalog
    }

    func refreshCatalog() async throws -> UnlockCatalog {
        guard let projectId = FirebaseApp.app()?.options.projectID,
              let base = URL(string: "https://\(projectId).web.app") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: base.appending(path: Self.path))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let catalog = try JSONDecoder().decode(UnlockCatalog.self, from: data)
        try cache.store(data, for: Self.path)
        return catalog
    }
}
