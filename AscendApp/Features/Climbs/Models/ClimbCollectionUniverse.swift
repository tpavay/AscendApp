import Foundation

/// One definition of what a climber's collection covers: every climb raceable
/// today, plus the retired climbs they already claimed. Home and Profile both
/// read it, so the same climber can never be shown two different fractions and
/// the numerator can never outgrow its denominator.
enum ClimbCollectionUniverse {
    static func climbs(
        availableClimbs: [Climb],
        claimedClimbIds: Set<String>,
        catalogueClimbs: [Climb]
    ) -> [Climb] {
        let availableIds = Set(availableClimbs.map(\.id))
        let retiredClaims = catalogueClimbs.filter { climb in
            !availableIds.contains(climb.id) && claimedClimbIds.contains(climb.id)
        }

        return availableClimbs + retiredClaims
    }

    static func collectedCount(
        claimedClimbIds: Set<String>,
        catalogueClimbs: [Climb]
    ) -> Int {
        catalogueClimbs.count { claimedClimbIds.contains($0.id) }
    }
}
