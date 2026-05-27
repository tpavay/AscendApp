import Foundation

struct ProfileFirstAscentSummary: Identifiable, Equatable {
    enum Kind: Equatable {
        case held(claimedAt: Date)
        case open
    }

    let climbId: String
    let climbName: String
    let locationText: String
    let tier: ClimbTier
    let targetSteps: Int
    let kind: Kind

    var id: String { climbId }
}
