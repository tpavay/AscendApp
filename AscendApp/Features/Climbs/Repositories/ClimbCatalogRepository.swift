import Foundation

protocol ClimbCatalogRepository: Sendable {
    func loadInitialCatalog() throws -> ClimbCatalogSnapshot
    func refreshCatalog() async throws -> ClimbCatalogSnapshot
}
