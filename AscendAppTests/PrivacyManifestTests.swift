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
            #expect(Set(declaration.purposes).isSubset(of: Self.validPurposes))
        }
    }

    @Test("Required reason declarations cover every API category used by the app and embedded SDKs")
    func requiredReasonDeclarationsMatchAccessContract() throws {
        let manifest = try loadManifest()
        let declarationsByType = Dictionary(
            grouping: manifest.accessedAPITypes,
            by: \AccessedAPIType.type
        )

        #expect(Set(declarationsByType.keys) == Set(Self.expectedAccessedAPITypes.keys))
        #expect(declarationsByType.values.allSatisfy { $0.count == 1 })

        for (type, expectedReasons) in Self.expectedAccessedAPITypes {
            let declaration = try #require(declarationsByType[type]?.first)
            #expect(Set(declaration.reasons) == expectedReasons)
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
    private static let productPersonalization = "NSPrivacyCollectedDataTypePurposeProductPersonalization"

    /// The complete set Apple accepts for `NSPrivacyCollectedDataTypePurposes`. A value outside it
    /// is not a recognized purpose, so the declaration it sits on reads as under-declared.
    private static let validPurposes: Set<String> = [
        "NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising",
        "NSPrivacyCollectedDataTypePurposeDeveloperAdvertising",
        analytics,
        productPersonalization,
        appFunctionality,
        "NSPrivacyCollectedDataTypePurposeOther"
    ]

    private static let expectedDataTypes: [String: ExpectedDataType] = [
        "NSPrivacyCollectedDataTypeEmailAddress": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypeName": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypeOtherDataTypes": .linked(analytics, productPersonalization, appFunctionality),
        "NSPrivacyCollectedDataTypeCoarseLocation": .linked(analytics, appFunctionality),
        "NSPrivacyCollectedDataTypeHealth": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypeFitness": .linked(analytics, productPersonalization, appFunctionality),
        "NSPrivacyCollectedDataTypePhotosorVideos": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypeUserID": .linked(analytics, appFunctionality),
        "NSPrivacyCollectedDataTypeDeviceID": .linked(analytics, appFunctionality),
        "NSPrivacyCollectedDataTypeCustomerSupport": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypeOtherUserContent": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypeProductInteraction": .linked(analytics, appFunctionality),
        "NSPrivacyCollectedDataTypePurchaseHistory": .linked(analytics, appFunctionality),
        "NSPrivacyCollectedDataTypeCrashData": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypePerformanceData": .linked(appFunctionality),
        "NSPrivacyCollectedDataTypeOtherDiagnosticData": .linked(appFunctionality)
    ]

    private static let expectedAccessedAPITypes: [String: Set<String>] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
        "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
        "NSPrivacyAccessedAPICategoryDiskSpace": ["E174.1"],
        "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"]
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
    let accessedAPITypes: [AccessedAPIType]

    private enum CodingKeys: String, CodingKey {
        case tracking = "NSPrivacyTracking"
        case trackingDomains = "NSPrivacyTrackingDomains"
        case collectedDataTypes = "NSPrivacyCollectedDataTypes"
        case accessedAPITypes = "NSPrivacyAccessedAPITypes"
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

private struct AccessedAPIType: Decodable {
    let type: String
    let reasons: [String]

    private enum CodingKeys: String, CodingKey {
        case type = "NSPrivacyAccessedAPIType"
        case reasons = "NSPrivacyAccessedAPITypeReasons"
    }
}
