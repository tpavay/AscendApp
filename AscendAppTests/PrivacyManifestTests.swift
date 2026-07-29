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

    @Test(
        "Every profile user property sent to analytics has an Analytics purpose on its data type",
        arguments: Self.analyticsProfileUserProperties
    )
    func analyticsProfileUserPropertiesDeclareAnalyticsPurpose(
        property: AnalyticsProfileUserProperty
    ) throws {
        let manifest = try loadManifest()
        let declaration = try #require(
            manifest.collectedDataTypes.first { $0.type == property.dataType },
            "\(property.name) is sent to Firebase Analytics and Mixpanel but \(property.dataType) is not declared"
        )

        #expect(declaration.purposes.contains(Self.analytics))
        #expect(declaration.linked)
        #expect(declaration.tracking == false)
    }

    /// Profile attributes the app attaches to Firebase Analytics and Mixpanel as account-level user
    /// properties. Adding a demographic user property without adding its row here - or stripping
    /// Analytics off the data type it belongs to - is exactly the under-declaration this guards.
    static let analyticsProfileUserProperties: [AnalyticsProfileUserProperty] = [
        AnalyticsProfileUserProperty(
            name: "profile_gender",
            dataType: "NSPrivacyCollectedDataTypeOtherDataTypes"
        ),
        AnalyticsProfileUserProperty(
            name: "profile_age_group",
            dataType: "NSPrivacyCollectedDataTypeOtherDataTypes"
        ),
        AnalyticsProfileUserProperty(
            name: "profile_weight_group",
            dataType: "NSPrivacyCollectedDataTypeHealth"
        ),
        AnalyticsProfileUserProperty(
            name: "profile_country",
            dataType: "NSPrivacyCollectedDataTypeCoarseLocation"
        )
    ]

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
        "NSPrivacyCollectedDataTypeHealth": .linked(analytics, appFunctionality),
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

struct AnalyticsProfileUserProperty: Sendable, CustomTestStringConvertible {
    let name: String
    let dataType: String

    var testDescription: String { "\(name) -> \(dataType)" }
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
