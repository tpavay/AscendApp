import Foundation
import Testing

struct PrivacyManifestTests {
    @Test("Collected data declarations match Ascend's off-device data contract")
    func collectedDataDeclarationsMatchOffDeviceDataContract() throws {
        let manifest = try loadManifest()
        let declarationsByType = Dictionary(
            grouping: manifest.collectedDataTypes,
            by: \CollectedDataType.type
        )

        #expect(manifest.tracking == false)
        #expect(manifest.trackingDomains.isEmpty)
        #expect(Set(declarationsByType.keys) == Set(Self.expectedDataTypes.keys))
        #expect(declarationsByType.values.allSatisfy { $0.count == 1 })

        for (type, expected) in Self.expectedDataTypes {
            let declaration = try #require(declarationsByType[type]?.first)
            #expect(declaration.linked == expected.linked)
            #expect(declaration.tracking == false)
            #expect(Set(declaration.purposes) == expected.purposes)
        }
    }

    private func loadManifest() throws -> PrivacyManifest {
        let repositoryRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repositoryRoot.appending(path: "AscendApp/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifestURL)
        return try PropertyListDecoder().decode(PrivacyManifest.self, from: data)
    }

    private static let analytics = "NSPrivacyCollectedDataTypePurposeAnalytics"
    private static let appFunctionality = "NSPrivacyCollectedDataTypePurposeAppFunctionality"
    private static let customerSupport = "NSPrivacyCollectedDataTypePurposeCustomerSupport"

    private static let expectedDataTypes: [String: ExpectedDataType] = [
        "NSPrivacyCollectedDataTypeEmailAddress": .linked(appFunctionality, customerSupport),
        "NSPrivacyCollectedDataTypeName": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypeOtherDataTypes": .linked(analytics, appFunctionality),
        "NSPrivacyCollectedDataTypeCoarseLocation": .linked(analytics, appFunctionality),
        "NSPrivacyCollectedDataTypeHealth": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypeFitness": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypePhotosorVideos": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypeUserID": .linked(analytics, appFunctionality),
        "NSPrivacyCollectedDataTypeDeviceID": .linked(analytics, appFunctionality),
        "NSPrivacyCollectedDataTypeOtherUserContent": .linked(customerSupport, appFunctionality),
        "NSPrivacyCollectedDataTypeProductInteraction": .linked(analytics, appFunctionality),
        "NSPrivacyCollectedDataTypePurchaseHistory": .linked(analytics, appFunctionality),
        "NSPrivacyCollectedDataTypeCrashData": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypePerformanceData": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypeOtherDiagnosticData": .linked(customerSupport, appFunctionality)
    ]
}

private struct ExpectedDataType: Sendable {
    let linked: Bool
    let purposes: Set<String>

    static func linked(_ purposes: String...) -> Self {
        Self(linked: true, purposes: Set(purposes))
    }
}

private struct PrivacyManifest: Decodable {
    let tracking: Bool
    let trackingDomains: [String]
    let collectedDataTypes: [CollectedDataType]

    private enum CodingKeys: String, CodingKey {
        case tracking = "NSPrivacyTracking"
        case trackingDomains = "NSPrivacyTrackingDomains"
        case collectedDataTypes = "NSPrivacyCollectedDataTypes"
    }
}

private struct CollectedDataType: Decodable {
    let type: String
    let linked: Bool
    let tracking: Bool
    let purposes: [String]

    private enum CodingKeys: String, CodingKey {
        case type = "NSPrivacyCollectedDataType"
        case linked = "NSPrivacyCollectedDataTypeLinked"
        case tracking = "NSPrivacyCollectedDataTypeTracking"
        case purposes = "NSPrivacyCollectedDataTypePurposes"
    }
}
