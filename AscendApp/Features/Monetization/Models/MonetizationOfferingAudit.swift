import Foundation

struct MonetizationOfferingAudit: Equatable {
    let expectedOfferingID: String
    let actualOfferingID: String?
    let missingProductIDs: [String]

    var hasExpectedOffering: Bool {
        actualOfferingID == expectedOfferingID
    }

    var isValid: Bool {
        hasExpectedOffering && missingProductIDs.isEmpty
    }

    var summary: String {
        let actual = actualOfferingID ?? "none"
        let missing = missingProductIDs.isEmpty ? "none" : missingProductIDs.joined(separator: ",")
        return "expected offering \(expectedOfferingID), got \(actual), missing products \(missing)"
    }

    var telemetryParameters: [String: TelemetryValue] {
        [
            "expected_offering_id": .string(expectedOfferingID),
            "actual_offering_id": .string(actualOfferingID ?? "none"),
            "missing_product_count": .int(missingProductIDs.count),
            "has_expected_offering": .bool(hasExpectedOffering)
        ]
    }
}
