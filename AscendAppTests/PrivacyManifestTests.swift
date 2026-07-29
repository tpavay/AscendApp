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
        "Each classified onboarding analytics attribute resolves to a declared Analytics data type",
        arguments: Self.analyticsProfileAttributes
    )
    func classifiedAnalyticsAttributesDeclareAnalyticsPurpose(
        attribute: AnalyticsProfileAttribute
    ) throws {
        let manifest = try loadManifest()
        let declaration = try #require(
            manifest.collectedDataTypes.first { $0.type == attribute.dataType },
            "\(attribute.name) reaches Firebase Analytics and Mixpanel but \(attribute.dataType) is not declared"
        )

        #expect(declaration.purposes.contains(Self.analytics))
        #expect(declaration.linked)
        #expect(declaration.tracking == false)
    }

    @Test("Every literally named OnboardingAnalyticsUserProperties property is classified")
    func onboardingUserPropertyNamesAreClassified() throws {
        let source = try loadOnboardingUserPropertySource()
        let pattern = try Regex(#"\bset\("([a-z0-9_]+)""#)
        let emitted = Set(
            source.matches(of: pattern).compactMap { $0[1].substring.map(String.init) }
        )

        #expect(emitted.isEmpty == false)
        #expect(emitted == Set(Self.analyticsProfileAttributes.filter(\.isUserProperty).map(\.name)))
    }

    /// Onboarding attributes that reach Firebase Analytics and Mixpanel, each mapped to the manifest
    /// data type it belongs to.
    ///
    /// `onboardingUserPropertyNamesAreClassified` pins the `isUserProperty` rows against the literal
    /// `set("…")` calls in `OnboardingAnalyticsUserProperties`, so a new user property added there
    /// fails until it is classified here. Two categories sit outside that scan and still have to be
    /// added by hand: attributes emitted as event parameters from elsewhere, such as
    /// `profile_height_group` on the body-metrics event in `PostAuthOnboardingFlowView`, and the goal
    /// properties whose names come from `knownGoalProperties` rather than a literal argument.
    static let analyticsProfileAttributes: [AnalyticsProfileAttribute] = [
        AnalyticsProfileAttribute(name: "profile_gender", dataType: otherDataTypes),
        AnalyticsProfileAttribute(name: "profile_age_group", dataType: otherDataTypes),
        AnalyticsProfileAttribute(name: "profile_weight_group", dataType: health),
        AnalyticsProfileAttribute(name: "profile_country", dataType: coarseLocation),
        AnalyticsProfileAttribute(name: "stair_stepper_exp", dataType: otherDataTypes),
        AnalyticsProfileAttribute(name: "exercise_level", dataType: otherDataTypes),
        AnalyticsProfileAttribute(name: "motivation", dataType: otherDataTypes),
        AnalyticsProfileAttribute(name: "planned_frequency", dataType: otherDataTypes),
        AnalyticsProfileAttribute(name: "goal_answer_count", dataType: otherDataTypes),
        AnalyticsProfileAttribute(name: "notifications_choice", dataType: otherDataTypes),
        AnalyticsProfileAttribute(name: "first_climb_id", dataType: otherDataTypes),
        AnalyticsProfileAttribute(name: "first_climb_tier", dataType: otherDataTypes),
        AnalyticsProfileAttribute(name: "first_climb_steps", dataType: otherDataTypes),
        AnalyticsProfileAttribute(name: "display_name_set", dataType: productInteraction),
        AnalyticsProfileAttribute(name: "profile_location_set", dataType: productInteraction),
        AnalyticsProfileAttribute(name: "onboarding_complete", dataType: productInteraction),
        AnalyticsProfileAttribute(
            name: "profile_height_group",
            dataType: health,
            isUserProperty: false
        )
    ]

    private func loadManifest() throws -> PrivacyManifest {
        let manifestURL = Self.repositoryRoot.appending(path: "AscendApp/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifestURL)
        return try PropertyListDecoder().decode(PrivacyManifest.self, from: data)
    }

    private func loadOnboardingUserPropertySource() throws -> String {
        let sourceURL = Self.repositoryRoot.appending(
            path: "AscendApp/Features/Onboarding/Analytics/OnboardingAnalyticsUserProperties.swift"
        )
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let health = "NSPrivacyCollectedDataTypeHealth"
    private static let coarseLocation = "NSPrivacyCollectedDataTypeCoarseLocation"
    private static let otherDataTypes = "NSPrivacyCollectedDataTypeOtherDataTypes"
    private static let productInteraction = "NSPrivacyCollectedDataTypeProductInteraction"

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

struct AnalyticsProfileAttribute: Sendable, CustomTestStringConvertible {
    let name: String
    let dataType: String
    var isUserProperty: Bool = true

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
