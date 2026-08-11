import Foundation

final class ProfileFirstAscentService: Sendable {
    static let shared = ProfileFirstAscentService()

    private let liveReplayService: any LiveReplayLeaderboardServicing

    init(liveReplayService: any LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared) {
        self.liveReplayService = liveReplayService
    }

    func loadFirstAscentSummaries(
        userId: String,
        climbs: [Climb],
        openLimit: Int = 4
    ) async -> (held: [ProfileFirstAscentSummary], open: [ProfileFirstAscentSummary]) {
        var held: [ProfileFirstAscentSummary] = []
        var open: [ProfileFirstAscentSummary] = []

        // A retired climb still answers who took it first, so held ascents survive
        // curation. Only a raceable climb can offer an unclaimed slot.
        for climb in climbs where climb.isAvailable || climb.releaseState == .hidden {
            let context = LiveReplayLeaderboardContext.liveClimb(
                climbId: climb.id,
                targetSteps: climb.referenceStepCount
            )

            guard let summary = try? await liveReplayService.fetchSummary(context: context) else {
                continue
            }

            if let firstAscent = summary.firstAscent {
                if firstAscent.userId == userId {
                    held.append(
                        ProfileFirstAscentSummary(
                            climbId: climb.id,
                            climbName: climb.name,
                            locationText: climb.displayLocation,
                            tier: climb.tier,
                            targetSteps: climb.referenceStepCount,
                            kind: .held(claimedAt: firstAscent.completedAt)
                        )
                    )
                }
            } else if climb.isAvailable, isClaimableOpenFirstAscent(summary), open.count < openLimit {
                open.append(
                    ProfileFirstAscentSummary(
                        climbId: climb.id,
                        climbName: climb.name,
                        locationText: climb.displayLocation,
                        tier: climb.tier,
                        targetSteps: climb.referenceStepCount,
                        kind: .open
                    )
                )
            }
        }

        return (
            held.sorted(by: firstAscentSort),
            open.sorted { $0.targetSteps < $1.targetSteps }
        )
    }

    private func firstAscentSort(
        lhs: ProfileFirstAscentSummary,
        rhs: ProfileFirstAscentSummary
    ) -> Bool {
        switch (lhs.kind, rhs.kind) {
        case (.held(let lhsDate), .held(let rhsDate)):
            lhsDate > rhsDate
        default:
            lhs.climbName < rhs.climbName
        }
    }

    private func isClaimableOpenFirstAscent(_ summary: LiveReplayLeaderboardSummary) -> Bool {
        summary.updatedAt != nil && summary.completedCount == 0
    }
}
