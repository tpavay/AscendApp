import FirebaseCore
import Foundation

struct HostedClimbCatalogRepository: ClimbCatalogRepository {
    enum RepositoryError: LocalizedError {
        case missingHostingProject
        case invalidResponse(statusCode: Int?)

        var errorDescription: String? {
            switch self {
            case .missingHostingProject:
                return "The Firebase project ID is unavailable for climb catalog loading."
            case .invalidResponse(let statusCode):
                if let statusCode {
                    return "Received an invalid climb catalog response (\(statusCode))."
                }
                return "Received an invalid climb catalog response."
            }
        }
    }

    private let cache: DiskAssetCache
    private let session: URLSession
    private let decoder: JSONDecoder
    private let manifestCacheKey = "climbs/manifest.json"
    private let bootstrapFeaturedClimbId = "empire-state-building"

    init(
        cache: DiskAssetCache = .climbCatalog,
        session: URLSession = .shared
    ) {
        self.cache = cache
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadInitialCatalog() throws -> ClimbCatalogSnapshot {
        if let cachedCatalog = try loadCachedCatalog() {
            return cachedCatalog
        }

        return try loadBootstrapCatalog()
    }

    func refreshCatalog() async throws -> ClimbCatalogSnapshot {
        let baseURL = try hostingBaseURL()
        let manifestURL = baseURL.appending(path: "climbs/manifest.json")
        let manifestData = try await fetchData(from: manifestURL)
        let manifest = try decoder.decode(ClimbCatalogManifest.self, from: manifestData)

        let catalogURL = catalogURL(for: manifest, baseURL: baseURL)
        let catalogData = try await fetchData(from: catalogURL)
        let climbs = try decoder.decode([Climb].self, from: catalogData)

        try cache.store(manifestData, for: manifestCacheKey)
        try cache.store(catalogData, for: manifest.catalogPath)

        return ClimbCatalogSnapshot(
            climbs: climbs,
            source: .remote,
            catalogVersion: manifest.catalogVersion,
            featuredClimbId: manifest.featuredClimbId,
            updatedAt: manifest.updatedAt
        )
    }

    private func loadCachedCatalog() throws -> ClimbCatalogSnapshot? {
        guard let manifestData = try cache.data(for: manifestCacheKey) else { return nil }
        let manifest = try decoder.decode(ClimbCatalogManifest.self, from: manifestData)
        guard let catalogData = try cache.data(for: manifest.catalogPath) else { return nil }

        let climbs = try decoder.decode([Climb].self, from: catalogData)
        return ClimbCatalogSnapshot(
            climbs: climbs,
            source: .diskCache,
            catalogVersion: manifest.catalogVersion,
            featuredClimbId: manifest.featuredClimbId,
            updatedAt: manifest.updatedAt
        )
    }

    private func loadBootstrapCatalog() throws -> ClimbCatalogSnapshot {
        let candidateURLs = [
            Bundle.main.url(forResource: "climbs", withExtension: "json"),
            Bundle.main.url(forResource: "climbs", withExtension: "json", subdirectory: "Features/Climbs/Resources"),
            Bundle.main.url(forResource: "climbs", withExtension: "json", subdirectory: "Resources")
        ]

        guard let url = candidateURLs.compactMap({ $0 }).first else {
            throw ClimbService.LoadError.missingBundledData
        }

        let data = try Data(contentsOf: url)
        let climbs = try decoder.decode([Climb].self, from: data)

        return ClimbCatalogSnapshot(
            climbs: climbs,
            source: .bootstrap,
            catalogVersion: 0,
            featuredClimbId: bootstrapFeaturedClimbId,
            updatedAt: nil
        )
    }

    private func hostingBaseURL() throws -> URL {
        guard let projectId = FirebaseApp.app()?.options.projectID,
              let baseURL = URL(string: "https://\(projectId).web.app") else {
            throw RepositoryError.missingHostingProject
        }

        return baseURL
    }

    private func catalogURL(for manifest: ClimbCatalogManifest, baseURL: URL) -> URL {
        if manifest.catalogPath.hasPrefix("/") {
            return baseURL.appending(path: String(manifest.catalogPath.dropFirst()))
        }

        return baseURL.appending(path: manifest.catalogPath)
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RepositoryError.invalidResponse(statusCode: nil)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RepositoryError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        return data
    }
}
