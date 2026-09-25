import Foundation

@testable import AscendApp

/// The catalog the app bundles as its bootstrap (`climbs.json`), decoded the way
/// `HostedClimbCatalogRepository` decodes it, for tests that need real climbs.
enum BundledClimbCatalog {
    static let climbs: [Climb] = {
        guard let url = Bundle.main.url(forResource: "climbs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Climb].self, from: data)) ?? []
    }()
}
