#if DEBUG
import Foundation

enum JourneyPrototypeBuilder {
    static func makeJourneys(from climbs: [Climb]) -> [JourneyPrototype] {
        let availableById = Dictionary(
            uniqueKeysWithValues: climbs
                .filter(\.isAvailable)
                .map { ($0.id, $0) }
        )

        return [
            makeJourney(
                id: "skyline-chain",
                title: "Skyline Chain",
                subtitle: "North America",
                thesis: "Claim the towers that taught cities to look up.",
                reward: "Finish the chain to unlock a skyline completion card.",
                accentHex: "AFCB00",
                climbIds: [
                    "statue-of-liberty",
                    "empire-state-building",
                    "chrysler-building",
                    "one-world-trade-center",
                    "cn-tower"
                ],
                climbsById: availableById
            ),
            makeJourney(
                id: "castle-circuit",
                title: "Castle Circuit",
                subtitle: "Fortresses",
                thesis: "Take the old walls one climb at a time.",
                reward: "Complete the circuit to mark every fortress claimed.",
                accentHex: "E0B85B",
                climbIds: [
                    "osaka-castle",
                    "neuschwanstein-castle",
                    "alhambra",
                    "acropolis-of-athens",
                    "abuna-yemata-guh"
                ],
                climbsById: availableById
            ),
            makeJourney(
                id: "world-icons",
                title: "World Icons",
                subtitle: "Global Route",
                thesis: "Cross the landmarks everyone knows. Rank on each one.",
                reward: "Clear the route to earn a global icons finish badge.",
                accentHex: "59D9FF",
                climbIds: [
                    "eiffel-tower",
                    "burj-khalifa",
                    "taipei-101",
                    "tokyo-skytree",
                    "osaka-castle"
                ],
                climbsById: availableById
            ),
            makeJourney(
                id: "summit-route",
                title: "Summit Route",
                subtitle: "Mountains",
                thesis: "Start high. Keep climbing until the route is closed.",
                reward: "Finish the route to lock in a summit series record.",
                accentHex: "7CFF6B",
                climbIds: [
                    "half-dome",
                    "pikes-peak",
                    "matterhorn",
                    "mount-fuji",
                    "mount-kilimanjaro"
                ],
                climbsById: availableById
            )
        ]
        .compactMap { $0 }
    }

    private static func makeJourney(
        id: String,
        title: String,
        subtitle: String,
        thesis: String,
        reward: String,
        accentHex: String,
        climbIds: [String],
        climbsById: [String: Climb]
    ) -> JourneyPrototype? {
        let climbs = climbIds.compactMap { climbsById[$0] }
        guard climbs.count >= 3 else { return nil }

        return JourneyPrototype(
            id: id,
            title: title,
            subtitle: subtitle,
            thesis: thesis,
            reward: reward,
            accentHex: accentHex,
            climbs: climbs
        )
    }
}
#endif
