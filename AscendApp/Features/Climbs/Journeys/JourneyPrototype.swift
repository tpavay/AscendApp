#if DEBUG
import CoreLocation
import SwiftUI

struct JourneyPrototype: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let thesis: String
    let reward: String
    let accentHex: String
    let climbs: [Climb]

    var accent: Color {
        Color(hex: accentHex)
    }

    var coordinates: [CLLocationCoordinate2D] {
        climbs.map(\.coordinate)
    }

    var totalSteps: Int {
        climbs.reduce(0) { $0 + $1.referenceStepCount }
    }

    func completedPrefixCount(in completedClimbIds: Set<String>) -> Int {
        var count = 0
        for climb in climbs {
            guard completedClimbIds.contains(climb.id) else { break }
            count += 1
        }
        return count
    }

    func progressText(in completedClimbIds: Set<String>) -> String {
        "\(completedPrefixCount(in: completedClimbIds))/\(climbs.count)"
    }

    func nextClimb(in completedClimbIds: Set<String>) -> Climb? {
        let nextIndex = completedPrefixCount(in: completedClimbIds)
        guard climbs.indices.contains(nextIndex) else { return nil }
        return climbs[nextIndex]
    }

    func steps(in completedClimbIds: Set<String>) -> [JourneyStep] {
        let completedCount = completedPrefixCount(in: completedClimbIds)

        return climbs.enumerated().map { index, climb in
            let status: JourneyStepStatus
            if index < completedCount {
                status = .completed
            } else if index == completedCount {
                status = .current
            } else {
                status = .locked
            }

            return JourneyStep(
                journeyId: id,
                index: index,
                climb: climb,
                status: status
            )
        }
    }
}
#endif
