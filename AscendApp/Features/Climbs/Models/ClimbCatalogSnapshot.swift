import Foundation

struct ClimbCatalogSnapshot {
    let climbs: [Climb]
    let source: ClimbCatalogSource
    let catalogVersion: Int
    let featuredClimbId: String?
    let updatedAt: Date?

    var visibleClimbs: [Climb] {
        climbs.filter(\.isVisibleOnGlobe)
    }

    var availableClimbs: [Climb] {
        climbs.filter(\.isAvailable)
    }

    var comingSoonClimbs: [Climb] {
        climbs.filter(\.isComingSoon)
    }
}
