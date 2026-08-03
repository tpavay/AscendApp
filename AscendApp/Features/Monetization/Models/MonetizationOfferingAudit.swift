import Foundation

struct MonetizationOfferingAudit: Equatable {
    let expectedOfferingID: String
    let currentOfferingID: String?
    let hasExpectedOffering: Bool
    let missingProductIDs: [String]

    var isLaunchCatalogComplete: Bool {
        hasExpectedOffering && missingProductIDs.isEmpty
    }

    var isServingExpectedOffering: Bool {
        currentOfferingID == expectedOfferingID
    }

    var summary: String {
        let missing = missingProductIDs.isEmpty ? "none" : missingProductIDs.joined(separator: ",")
        return "offering \(expectedOfferingID) present \(hasExpectedOffering), missing products \(missing)"
    }

    var telemetryParameters: [String: TelemetryValue] {
        [
            "expected_offering_id": .string(expectedOfferingID),
            "has_expected_offering": .bool(hasExpectedOffering),
            "missing_product_count": .int(missingProductIDs.count)
        ]
    }
}
