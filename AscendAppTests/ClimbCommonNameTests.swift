import Foundation
import Testing
@testable import AscendApp

/// `commonName` is the name a city still uses for a renamed landmark. It is an
/// optional, data-only addition: older catalogues omit the key entirely, and no
/// surface renders it yet, so the contract worth guarding is that its absence
/// decodes cleanly and its presence never displaces `name`.
struct ClimbCommonNameTests {
    // MARK: - Decoding

    @Test
    func absentCommonNameDecodesAsNilRatherThanFailing() throws {
        let climb = try decodeClimb(from: Self.catalogueEntryJSON(commonName: nil))

        #expect(climb.commonName == nil)
        #expect(climb.name == "875 North Michigan Avenue")
    }

    @Test
    func presentCommonNameDecodesAlongsideTheOfficialName() throws {
        let climb = try decodeClimb(from: Self.catalogueEntryJSON(commonName: "John Hancock Center"))

        #expect(climb.commonName == "John Hancock Center")
        #expect(climb.name == "875 North Michigan Avenue")
    }

    @Test
    func encodingOmitsTheKeyWhenNoCommonNameExists() throws {
        let withoutCommonName = try decodeClimb(from: Self.catalogueEntryJSON(commonName: nil))
        let withCommonName = try decodeClimb(from: Self.catalogueEntryJSON(commonName: "John Hancock Center"))

        let omitted = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(withoutCommonName)
        ) as? [String: Any]
        let written = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(withCommonName)
        ) as? [String: Any]

        #expect(omitted?["commonName"] == nil)
        #expect(written?["commonName"] as? String == "John Hancock Center")
    }

    // MARK: - Shipped catalogue

    @Test
    func onlyTheRenamedChicagoLandmarkCarriesACommonName() throws {
        let climbs = try Self.bundledCatalog()

        let named = climbs.filter { $0.commonName != nil }

        #expect(named.map(\.id) == ["875-north-michigan-avenue"])
    }

    @Test
    func theRenamedChicagoLandmarkKeepsItsOfficialNameAndAddsTheFormerOne() throws {
        let climbs = try Self.bundledCatalog()

        let chicago = try #require(climbs.first { $0.id == "875-north-michigan-avenue" })

        #expect(chicago.name == "875 North Michigan Avenue")
        #expect(chicago.commonName == "John Hancock Center")
    }

    // MARK: - Helpers

    private func decodeClimb(from json: String) throws -> Climb {
        try JSONDecoder().decode(Climb.self, from: Data(json.utf8))
    }

    private static func catalogueEntryJSON(commonName: String?) -> String {
        let commonNameLine = commonName.map { "\"commonName\": \"\($0)\"," } ?? ""
        return """
        {
          "id": "875-north-michigan-avenue",
          "name": "875 North Michigan Avenue",
          \(commonNameLine)
          "city": "Chicago",
          "country": "United States",
          "continent": "North America",
          "latitude": 41.8988813,
          "longitude": -87.6230962,
          "totalHeightMeters": 343.7,
          "totalHeightFeet": 1127.6,
          "realClimbableHeightMeters": null,
          "realClimbableHeightFeet": null,
          "totalSteps": 1890,
          "realStairCount": 1632,
          "calculatedFloors": 94,
          "category": "skyscraper",
          "tier": "gold",
          "tags": ["x-braced", "chicago", "world tour"],
          "funFact": "Fact.",
          "sourceURL": "https://www.towerrunning.com/races/r3137/",
          "releaseState": "comingSoon"
        }
        """
    }

    private static let bundledCatalogURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "AscendApp/Features/Climbs/Resources/climbs.json")

    private static func bundledCatalog() throws -> [Climb] {
        let data = try Data(contentsOf: bundledCatalogURL)
        return try JSONDecoder().decode([Climb].self, from: data)
    }
}
