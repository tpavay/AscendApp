import Foundation

struct ClimbCatalogSnapshot {
    let climbs: [Climb]
    let source: ClimbCatalogSource
    let catalogVersion: Int
    let featuredClimbId: String?
    let updatedAt: Date?

    var publishedClimbs: [Climb] {
        climbs.filter(\.isPublished)
    }
}
