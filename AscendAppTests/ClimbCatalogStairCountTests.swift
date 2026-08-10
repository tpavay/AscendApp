import Foundation
import Testing
@testable import AscendApp

/// A climb's step count is its race distance, so the catalogue's honesty about
/// that number is a shipped contract rather than a data-quality nicety.
///
/// `totalSteps` is the architectural-height derivation and is not a route;
/// `realStairCount` is the verified count of the steps people actually climb.
/// Sources for every populated number live in `docs/climb-real-stair-counts.md`.
struct ClimbCatalogStairCountTests {
    // MARK: - referenceStepCount

    @Test
    func referenceStepCountPrefersRealStairCountOverHeightDerivedTotal() {
        let corrected = makeClimb(totalSteps: 2_096, realStairCount: 1_576)

        #expect(corrected.referenceStepCount == 1_576)
        #expect(corrected.totalSteps == 2_096)
    }

    @Test
    func referenceStepCountFallsBackToTotalStepsWhenNoRealCountIsVerified() {
        let unverified = makeClimb(totalSteps: 1_705, realStairCount: nil)

        #expect(unverified.referenceStepCount == 1_705)
    }

    @Test
    func referenceStepCountPrefersARealCountLargerThanTheDerivedTotal() {
        // Gateway Arch: the real stairway is longer than the height derivation,
        // so the preference is not "whichever is smaller".
        let arch = makeClimb(totalSteps: 1_056, realStairCount: 1_076)

        #expect(arch.referenceStepCount == 1_076)
    }

    @Test
    func referenceHeightPrefersTheClimbedVerticalOverArchitecturalHeight() {
        let tokyoTower = makeClimb(
            totalHeightMeters: 333,
            totalHeightFeet: 1_092.5,
            realClimbableHeightMeters: 150,
            realClimbableHeightFeet: 492.1
        )

        #expect(tokyoTower.referenceHeightMeters == 150)
        #expect(tokyoTower.referenceHeightFeet == 492.1)
        #expect(tokyoTower.totalHeightMeters == 333)
    }

    // MARK: - Tier derivation

    @Test
    func tierDerivesFromTheCorrectedReferenceCountNotTheHeightDerivedTotal() {
        // Tokyo Tower's 1,832 comes from the 333 m antenna and corresponds to no
        // route; the raced distance is 500, which is a bronze sprint.
        let tokyoTower = makeClimb(totalSteps: 1_832, realStairCount: 500)

        #expect(ClimbTier(steps: tokyoTower.totalSteps) == .gold)
        #expect(ClimbTier(steps: tokyoTower.referenceStepCount) == .bronze)
    }

    @Test(arguments: [
        (296, ClimbTier.common),
        (300, ClimbTier.bronze),
        (599, ClimbTier.bronze),
        (600, ClimbTier.silver),
        (1_199, ClimbTier.silver),
        (1_200, ClimbTier.gold),
        (2_099, ClimbTier.gold),
        (2_100, ClimbTier.diamond),
        (3_499, ClimbTier.diamond),
        (3_500, ClimbTier.epic)
    ])
    func tierThresholdsBracketTheCorrectedCounts(steps: Int, expected: ClimbTier) {
        #expect(ClimbTier(steps: steps) == expected)
    }

    // MARK: - Shipped catalogue

    @Test
    func bundledAndHostedCataloguesAreByteIdentical() throws {
        let bundled = try Data(contentsOf: Self.bundledCatalogURL)
        let hosted = try Data(contentsOf: Self.hostedCatalogURL)

        #expect(bundled == hosted)
    }

    @Test
    func worldTour2026AdditionsDecodeWithRaceableReleaseAndHonestTierData() throws {
        let expectedIDs: Set<String> = [
            "ping-an-finance-centre", "ctf-finance-centre-guangzhou",
            "shanghai-world-financial-center",
            "sommerbergbahn-stair", "capitamall-one", "central-plaza-hong-kong",
            "875-north-michigan-avenue", "dc-tower-1", "yingkai-square",
            "tk-elevator-test-tower", "varso-tower", "tianjin-tv-tower",
            "macau-tower", "frasers-tower", "torre-reforma", "messeturm-frankfurt",
            "sky-tower-wroclaw", "gran-hotel-bali", "tallinn-tv-tower", "rondo-1",
            "post-tower", "sky-tower-bucharest", "koelnturm", "torre-glories",
            "az-tower", "hyatt-regency-barcelona-tower", "messeturm-basel",
            "pyramidenkogel", "ufo-tower-bratislava"
        ]
        let additions = try Self.bundledCatalog().filter { expectedIDs.contains($0.id) }

        #expect(Set(additions.map(\.id)) == expectedIDs)
        #expect(additions.count == 29)
        #expect(additions.allSatisfy { $0.releaseState == .available })
        #expect(additions.allSatisfy { $0.tier == ClimbTier(steps: $0.referenceStepCount) })

        let capitaMall = try #require(additions.first { $0.id == "capitamall-one" })
        #expect(capitaMall.realStairCount == nil)
        #expect(capitaMall.referenceStepCount == capitaMall.totalSteps)
    }

    @Test
    func everyCatalogueTierMatchesItsReferenceStepCount() throws {
        let climbs = try Self.bundledCatalog()

        let mismatched = climbs.filter { $0.tier != ClimbTier(steps: $0.referenceStepCount) }

        #expect(
            mismatched.isEmpty,
            """
            Tier must be recomputed from referenceStepCount: \
            \(mismatched.map { "\($0.id) is \($0.tier.rawValue) at \($0.referenceStepCount) steps" })
            """
        )
    }

    @Test
    func correctedClimbsShipTheVerifiedRaceDistanceAndItsTier() throws {
        // Spot checks against docs/climb-real-stair-counts.md. Each pair is a
        // climb whose fabricated distance changed the tier it races in.
        let expected: [String: (steps: Int, tier: ClimbTier)] = [
            "empire-state-building": (1_576, .gold),
            "taipei-101": (2_046, .gold),
            "burj-khalifa": (2_909, .diamond),
            "cn-tower": (1_776, .gold),
            "tokyo-tower": (500, .bronze),
            "monserrate": (1_605, .gold),
            "leaning-tower-of-pisa": (296, .common),
            "charminar": (149, .common)
        ]

        let climbs = try Self.bundledCatalog()
        for (id, expectation) in expected {
            let climb = try #require(climbs.first { $0.id == id }, "\(id) missing from catalogue")

            #expect(climb.realStairCount == expectation.steps, "\(id) realStairCount")
            #expect(climb.referenceStepCount == expectation.steps, "\(id) referenceStepCount")
            #expect(climb.tier == expectation.tier, "\(id) tier")
        }
    }

    @Test
    func catalogueTotalStepsRemainTheArchitecturalHeightDerivation() throws {
        // `totalSteps` is round(totalHeightMeters * 5.5) and stays that way:
        // correcting a distance populates realStairCount instead. Guarding this
        // is what stops a future correction from being written to the wrong field.
        let climbs = try Self.bundledCatalog()

        let rewritten = climbs.filter {
            $0.totalSteps != Int(($0.totalHeightMeters * 5.5).rounded())
        }

        #expect(
            rewritten.isEmpty,
            "totalSteps must stay height-derived: \(rewritten.map(\.id))"
        )
    }

    @Test
    func climbsWithoutAVerifiedCountAdmitTheGapRatherThanGuessing() throws {
        // A null realStairCount is the honest state for a climb with no
        // defensible published figure; it must not be back-filled from height.
        let climbs = try Self.bundledCatalog()

        let unverified = climbs.filter { $0.realStairCount == nil }

        #expect(unverified.isEmpty == false)
    }

    @Test
    func everyCatalogueFloorCountAgreesWithItsReferenceStepCount() throws {
        // FLOORS renders beside STEPS on climb detail, so a floor count still
        // derived from architectural height contradicts a corrected distance:
        // Monserrate read 1,605 steps over 876 floors, Tokyo Tower 500 over 93.
        // Floors are either the route's published storey count or
        // round(referenceStepCount / 19.8); either way the pair stays plausible.
        // Sources for the published counts live in docs/climb-real-stair-counts.md.
        let climbs = try Self.bundledCatalog()

        let implausible = climbs.filter { climb in
            guard climb.calculatedFloors > 0 else { return true }
            let stepsPerFloor = Double(climb.referenceStepCount) / Double(climb.calculatedFloors)
            // Frasers Tower's published 1,256-step, 39-floor route is 32.2
            // steps per floor, so 33 is the smallest honest upper bound.
            return stepsPerFloor < 15 || stepsPerFloor > 33
        }

        #expect(
            implausible.isEmpty,
            """
            calculatedFloors must derive from referenceStepCount, not from height: \
            \(implausible.map { "\($0.id) is \($0.referenceStepCount) steps over \($0.calculatedFloors) floors" })
            """
        )
    }

    // MARK: - Helpers

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

    private func makeClimb(
        totalHeightMeters: Double = 381,
        totalHeightFeet: Double = 1_250,
        realClimbableHeightMeters: Double? = nil,
        realClimbableHeightFeet: Double? = nil,
        totalSteps: Int = 2_096,
        realStairCount: Int? = nil
    ) -> Climb {
        Climb(
            id: "test-climb",
            name: "Test Climb",
            city: "City",
            country: "Country",
            continent: "Continent",
            latitude: 0,
            longitude: 0,
            totalHeightMeters: totalHeightMeters,
            totalHeightFeet: totalHeightFeet,
            realClimbableHeightMeters: realClimbableHeightMeters,
            realClimbableHeightFeet: realClimbableHeightFeet,
            totalSteps: totalSteps,
            realStairCount: realStairCount,
            calculatedFloors: max(1, (realStairCount ?? totalSteps) / 20),
            category: "skyscraper",
            tier: ClimbTier(steps: realStairCount ?? totalSteps),
            tags: [],
            funFact: "Fact.",
            sourceURL: "https://example.com"
        )
    }
}
