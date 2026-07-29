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
        "Each classified analytics attribute resolves to a linked data type declared for Analytics",
        arguments: Self.analyticsAttributes
    )
    func classifiedAnalyticsAttributesDeclareAnalyticsPurpose(
        attribute: AnalyticsAttribute
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

    @Test("Every literally named user property in the app target is classified")
    func userPropertyCallSitesAreFullyClassified() throws {
        let sources = appTargetSwiftSources()
        #expect(sources.isEmpty == false)

        let directCall = try Regex(#"setUserProperty\("([A-Za-z0-9_]+)""#)
        let wrapperCall = try Regex(#"\bset\("([A-Za-z0-9_]+)""#)
        var emitted: Set<String> = []

        for url in sources {
            let source = try String(contentsOf: url, encoding: .utf8)
            emitted.formUnion(source.captures(of: directCall))

            if url.lastPathComponent == Self.userPropertyWrapperFile {
                emitted.formUnion(source.captures(of: wrapperCall))
            }
        }

        let classified = Set(
            Self.analyticsAttributes.filter(\.isScannedUserProperty).map(\.name)
        )
        #expect(emitted == classified)
    }

    @Test("Indirectly named analytics attributes still appear in the source that emits them")
    func indirectlyNamedAttributesAppearInSource() throws {
        let sources = appTargetSwiftSources()

        for attribute in Self.analyticsAttributes {
            guard case .literal(let fileName) = attribute.origin else { continue }
            let url = try #require(
                sources.first { $0.lastPathComponent == fileName },
                "\(fileName) no longer exists in the app target"
            )
            let source = try String(contentsOf: url, encoding: .utf8)

            #expect(
                source.contains("\"\(attribute.name)\""),
                "\(attribute.name) is no longer emitted by \(fileName)"
            )
        }
    }

    @Test(
        "Every data type an analytics event parameter can land in is declared for Analytics",
        arguments: Self.eventParameterDataTypes
    )
    func eventParameterDataTypesAreDeclaredForAnalytics(dataType: String) throws {
        let manifest = try loadManifest()
        let declaration = try #require(
            manifest.collectedDataTypes.first { $0.type == dataType },
            "event parameters reach \(dataType) but it is not declared"
        )

        #expect(declaration.purposes.contains(Self.analytics))
        #expect(declaration.linked)
        #expect(declaration.tracking == false)
    }

    /// The categories analytics event parameters resolve to across the hand inventory: banded body
    /// values, workout metrics, paywall and purchase fields, the location filter, onboarding answers,
    /// interaction fields, and the Superwall skip-reason and error descriptions that ride
    /// `TelemetryRecord`'s default `destinations: [.analytics]`.
    static let eventParameterDataTypes: [String] = [
        health,
        fitness,
        purchaseHistory,
        coarseLocation,
        otherDataTypes,
        productInteraction,
        otherDiagnosticData
    ]

    /// Every analytics attribute the app can attach to a Firebase Analytics or Mixpanel identity,
    /// mapped to the manifest data type that has to declare it. Mixpanel receives all of them after
    /// `identify`, so each one is linked to the user.
    ///
    /// The two origins differ in how much the tests can promise:
    ///
    /// - `.scannedUserProperty` names are pinned by `userPropertyCallSitesAreFullyClassified`, which
    ///   scans every Swift file under `AscendApp/` for literal `setUserProperty("…")` calls plus the
    ///   `set("…")` wrapper inside `OnboardingAnalyticsUserProperties`. A new literal user property
    ///   anywhere in the app target fails that test until it is classified here.
    /// - `.literal(inFile:)` names are the ones that scan cannot see: goal properties assembled from
    ///   `knownGoalProperties`, and event parameters carrying body or demographic values.
    ///   `indirectlyNamedAttributesAppearInSource` only checks that each still appears in the file it
    ///   comes from, so a newly added one has to be classified by hand.
    ///
    /// Event parameters beyond the three listed here are not scanned and are not established by the
    /// user-property scan at all. They are inventoried by hand in the untracked local working file
    /// `data/asc-app-privacy-answers.md`, which is not part of the repository. Their classification can
    /// depend on call-site context rather than on the parameter name: `selected_value` on
    /// `leaderboard_filter_changed` is Health when `filter_type` is `body_weight`, Other Data Types
    /// when it is `age_group`, and Coarse Location when it is `location`. Across the inventory those
    /// parameters land in Fitness, Purchase History, Health, and Coarse Location as well as Product
    /// Interaction and Other Data Types, so no blanket claim about them is made here.
    /// `eventParameterDataTypesAreDeclaredForAnalytics` checks only that every category they can land
    /// in is declared linked and non-tracking with the Analytics purpose.
    static let analyticsAttributes: [AnalyticsAttribute] = [
        AnalyticsAttribute(name: "profile_weight_group", dataType: health),
        AnalyticsAttribute(name: "profile_gender", dataType: otherDataTypes),
        AnalyticsAttribute(name: "profile_age_group", dataType: otherDataTypes),
        AnalyticsAttribute(name: "profile_country", dataType: coarseLocation),
        AnalyticsAttribute(name: "stair_stepper_exp", dataType: fitness),
        AnalyticsAttribute(name: "exercise_level", dataType: fitness),
        AnalyticsAttribute(name: "motivation", dataType: fitness),
        AnalyticsAttribute(name: "planned_frequency", dataType: fitness),
        AnalyticsAttribute(name: "goal_answer_count", dataType: fitness),
        AnalyticsAttribute(name: "notifications_choice", dataType: otherDataTypes),
        AnalyticsAttribute(name: "first_climb_id", dataType: otherDataTypes),
        AnalyticsAttribute(name: "first_climb_tier", dataType: otherDataTypes),
        AnalyticsAttribute(name: "first_climb_steps", dataType: otherDataTypes),
        AnalyticsAttribute(name: "display_name_set", dataType: productInteraction),
        AnalyticsAttribute(name: "profile_location_set", dataType: productInteraction),
        AnalyticsAttribute(name: "onboarding_complete", dataType: productInteraction),
        AnalyticsAttribute(name: "name_inputted", dataType: productInteraction),
        AnalyticsAttribute(name: "division_inputted", dataType: productInteraction),
        AnalyticsAttribute(name: "age_inputted", dataType: productInteraction),
        AnalyticsAttribute(name: "body_metrics_inputted", dataType: productInteraction),
        AnalyticsAttribute(name: "location_inputted", dataType: productInteraction),
        AnalyticsAttribute(name: "notifications_inputted", dataType: productInteraction),
        AnalyticsAttribute(name: "first_climb_selected", dataType: productInteraction),
        AnalyticsAttribute(
            name: "goal_lose_weight",
            dataType: fitness,
            origin: .literal(inFile: userPropertyWrapperFile)
        ),
        AnalyticsAttribute(
            name: "goal_build_endurance",
            dataType: fitness,
            origin: .literal(inFile: userPropertyWrapperFile)
        ),
        AnalyticsAttribute(
            name: "goal_track_progress",
            dataType: fitness,
            origin: .literal(inFile: userPropertyWrapperFile)
        ),
        AnalyticsAttribute(
            name: "goal_exciting_workouts",
            dataType: fitness,
            origin: .literal(inFile: userPropertyWrapperFile)
        ),
        AnalyticsAttribute(
            name: "goal_healthier_life",
            dataType: fitness,
            origin: .literal(inFile: userPropertyWrapperFile)
        ),
        AnalyticsAttribute(
            name: "profile_height_group",
            dataType: health,
            origin: .literal(inFile: "PostAuthOnboardingFlowView.swift")
        ),
        AnalyticsAttribute(
            name: "body_weight_filter",
            dataType: health,
            origin: .literal(inFile: "LeaderboardAnalyticsEvent.swift")
        ),
        AnalyticsAttribute(
            name: "age_group",
            dataType: otherDataTypes,
            origin: .literal(inFile: "LeaderboardAnalyticsEvent.swift")
        )
    ]

    private func loadManifest() throws -> PrivacyManifest {
        let manifestURL = Self.repositoryRoot.appending(path: "AscendApp/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifestURL)
        return try PropertyListDecoder().decode(PrivacyManifest.self, from: data)
    }

    private func appTargetSwiftSources() -> [URL] {
        let root = Self.repositoryRoot.appending(path: "AscendApp")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }

    private static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let userPropertyWrapperFile = "OnboardingAnalyticsUserProperties.swift"

    private static let analytics = "NSPrivacyCollectedDataTypePurposeAnalytics"
    private static let appFunctionality = "NSPrivacyCollectedDataTypePurposeAppFunctionality"
    private static let productPersonalization = "NSPrivacyCollectedDataTypePurposeProductPersonalization"

    private static let health = "NSPrivacyCollectedDataTypeHealth"
    private static let fitness = "NSPrivacyCollectedDataTypeFitness"
    private static let coarseLocation = "NSPrivacyCollectedDataTypeCoarseLocation"
    private static let otherDataTypes = "NSPrivacyCollectedDataTypeOtherDataTypes"
    private static let productInteraction = "NSPrivacyCollectedDataTypeProductInteraction"
    private static let purchaseHistory = "NSPrivacyCollectedDataTypePurchaseHistory"
    private static let otherDiagnosticData = "NSPrivacyCollectedDataTypeOtherDiagnosticData"

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
        "NSPrivacyCollectedDataTypeOtherDiagnosticData": .linked(analytics, appFunctionality)
    ]

    private static let expectedAccessedAPITypes: [String: Set<String>] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
        "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
        "NSPrivacyAccessedAPICategoryDiskSpace": ["E174.1"],
        "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"]
    ]
}

struct AnalyticsAttribute: Sendable, CustomTestStringConvertible {
    enum Origin: Sendable {
        case scannedUserProperty
        case literal(inFile: String)
    }

    let name: String
    let dataType: String
    var origin: Origin = .scannedUserProperty

    var isScannedUserProperty: Bool {
        if case .scannedUserProperty = origin { return true }
        return false
    }

    var testDescription: String { "\(name) -> \(dataType)" }
}

private extension String {
    func captures(of pattern: Regex<AnyRegexOutput>) -> [String] {
        matches(of: pattern).compactMap { $0[1].substring.map(String.init) }
    }
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
