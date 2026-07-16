import Foundation

struct ClimbCatalogManifest: Codable {
    let catalogVersion: Int
    let catalogPath: String
    let featuredClimbId: String?
    let updatedAt: Date?
}
