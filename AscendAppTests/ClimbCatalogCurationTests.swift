import Foundation
import Testing
@testable import AscendApp

struct ClimbCatalogCurationTests {
    @Test("Deleted landmarks no longer decode from the racing catalogue", .bug(id: 440))
    func deletedLandmarksAreAbsent() throws {
        let catalogueIDs = Set(try Self.bundledCatalog().map(\.id))

        #expect(
            Self.deletedClimbIDs.isDisjoint(with: catalogueIDs),
            "Deleted climb IDs still decode: \(Self.deletedClimbIDs.intersection(catalogueIDs).sorted())"
        )
    }

    @Test("Mountains remain stored but stay out of racing surfaces", .bug(id: 440))
    func hiddenMountainsAreNotRaceable() throws {
        let snapshot = try Self.bundledSnapshot()
        let hiddenIDs = Set(snapshot.climbs.filter { $0.releaseState == .hidden }.map(\.id))
        let raceableIDs = Set(snapshot.availableClimbs.map(\.id))

        #expect(hiddenIDs == Self.hiddenMountainIDs)
        #expect(Self.hiddenMountainIDs.isDisjoint(with: raceableIDs))
    }

    @Test("Unverified stair routes remain visible but cannot start a race", .bug(id: 465))
    func comingSoonClimbsAreNotRaceable() throws {
        let snapshot = try Self.bundledSnapshot()
        let comingSoonIDs = Set(snapshot.comingSoonClimbs.map(\.id))
        let raceableIDs = Set(snapshot.availableClimbs.map(\.id))

        #expect(comingSoonIDs == Self.comingSoonClimbIDs)
        #expect(Self.comingSoonClimbIDs.isDisjoint(with: raceableIDs))
        #expect(Self.comingSoonClimbIDs.isSubset(of: Set(snapshot.visibleClimbs.map(\.id))))
    }

    @Test("The curated catalogue ships the approved 58/21/8 distribution", .bug(id: 465))
    func curatedCatalogueCounts() throws {
        let snapshot = try Self.bundledSnapshot()
        let hiddenCount = snapshot.climbs.count(where: { $0.releaseState == .hidden })

        #expect(snapshot.climbs.count == 87)
        #expect(snapshot.availableClimbs.count == 58)
        #expect(hiddenCount == 21)
        #expect(snapshot.comingSoonClimbs.count == 8)
        #expect(snapshot.climbs.allSatisfy { $0.releaseState != .disabled })
        #expect(Set(snapshot.climbs.map(\.id)).count == snapshot.climbs.count)
    }

    @Test("The hosted and bundled catalogues stay byte-identical", .bug(id: 440))
    func hostedAndBundledCataloguesMatch() throws {
        let bundled = try Data(contentsOf: Self.bundledCatalogURL)
        let hosted = try Data(contentsOf: Self.hostedCatalogURL)

        #expect(bundled == hosted)
    }

    @MainActor
    @Test("Only a raceable climb offers a live climb action", .bug(id: 440))
    func onlyAvailableClimbsCanStartARace() throws {
        let snapshot = try Self.bundledSnapshot()

        for climb in snapshot.climbs {
            let viewModel = ClimbDetailViewModel(climb: climb)

            switch climb.releaseState {
            case .available:
                #expect(viewModel.isActionEnabled)
                #expect(viewModel.actionTitle == "Start Live Climb")
            case .comingSoon:
                #expect(!viewModel.isActionEnabled)
                #expect(viewModel.actionTitle == "Coming Soon")
            case .hidden, .disabled:
                #expect(!viewModel.isActionEnabled)
                // A retired mountain is reachable through history, and calling it
                // "Coming Soon" promises a race that is never coming.
                #expect(viewModel.actionTitle == "Not Raceable")
            }
        }
    }

    private static let deletedClimbIDs: Set<String> = [
        "abuna-yemata-guh",
        "acropolis-of-athens",
        "alhambra",
        "cairo-tower",
        "chrysler-building",
        "gateway-arch",
        "gran-torre-santiago",
        "hallgrimskirkja",
        "machu-picchu",
        "moscow-state-university-main-building",
        "neuschwanstein-castle",
        "palacio-salvo",
        "sugarloaf-mountain",
        "table-mountain",
        "tokyo-skytree",
        "transamerica-pyramid",
        "washington-monument"
    ]

    private static let hiddenMountainIDs: Set<String> = [
        "aconcagua",
        "aoraki-mount-cook",
        "denali",
        "half-dome",
        "kunanyi-mount-wellington",
        "llaima-volcano",
        "matterhorn",
        "mont-blanc",
        "mount-cameroon",
        "mount-everest",
        "mount-etna",
        "mount-fuji",
        "mount-kenya",
        "mount-kilimanjaro",
        "mount-kinabalu",
        "mount-kosciuszko",
        "mount-roraima",
        "mount-taranaki",
        "mount-whitney",
        "pikes-peak",
        "torres-del-paine"
    ]

    private static let comingSoonClimbIDs: Set<String> = [
        // CapitaMall ONE has no published course distance, so racing it would set
        // every time against round(totalHeightMeters * 5.5) rather than a route.
        "capitamall-one",
        "marina-bay-sands",
        "n-seoul-tower",
        "osaka-castle",
        "petronas-towers",
        "sagrada-familia",
        "the-shard",
        "voortrekker-monument"
    ]

    private static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let bundledCatalogURL = repositoryRoot
        .appending(path: "AscendApp/Features/Climbs/Resources/climbs.json")

    private static let hostedCatalogURL = repositoryRoot
        .appending(path: "web/public/climbs/catalog-v1.json")

    private static func bundledCatalog() throws -> [Climb] {
        let data = try Data(contentsOf: bundledCatalogURL)
        return try JSONDecoder().decode([Climb].self, from: data)
    }

    private static func bundledSnapshot() throws -> ClimbCatalogSnapshot {
        ClimbCatalogSnapshot(
            climbs: try bundledCatalog(),
            source: .bootstrap,
            catalogVersion: 0,
            featuredClimbId: nil,
            updatedAt: nil
        )
    }
}
