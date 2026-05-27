import Foundation

struct ProfileCollectionClaimedClimb: Equatable {
    let climb: Climb
    let claimedAt: Date
}

enum ProfileCollectionCardItem: Identifiable, Equatable {
    case claimed(ProfileCollectionClaimedClimb)
    case unclaimed(Climb)

    var id: String {
        switch self {
        case .claimed(let completion):
            return "claimed-\(completion.climb.id)"
        case .unclaimed(let climb):
            return "unclaimed-\(climb.id)"
        }
    }

    var climb: Climb {
        switch self {
        case .claimed(let completion):
            return completion.climb
        case .unclaimed(let climb):
            return climb
        }
    }

    var claimedAt: Date? {
        guard case .claimed(let completion) = self else { return nil }
        return completion.claimedAt
    }
}

struct ProfileCollectionSummary: Equatable {
    let collectedCount: Int
    let catalogCount: Int
    let previewCards: [ProfileCollectionCardItem]
    let launchedCards: [ProfileCollectionCardItem]
    let comingSoonClimbs: [Climb]
}
