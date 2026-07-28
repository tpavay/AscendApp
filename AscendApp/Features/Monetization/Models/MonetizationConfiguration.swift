import Foundation

struct MonetizationConfiguration: Equatable {
    enum RevenueCatStoreMode: Equatable {
        case unavailable
        case appStore
        case testStore
    }

    static let live = MonetizationConfiguration()

    static let revenueCatAPIKeyInfoKey = "AscendRevenueCatAPIKey"
    static let revenueCatTestAPIKeyInfoKey = "AscendRevenueCatTestAPIKey"
    static let revenueCatUseTestStoreInfoKey = "AscendUseRevenueCatTestStore"
    static let superwallAPIKeyInfoKey = "AscendSuperwallAPIKey"
    static let superwallTestModeInfoKey = "AscendSuperwallTestMode"

    /// Mirrored by `PLACEHOLDER_API_KEY_PREFIX` in
    /// `scripts/lib/monetization-build-settings.mjs`, which gates staging and
    /// production archives on the same prefix.
    static let placeholderAPIKeyPrefix = "REPLACE_ME_"

    static let apiKeyInfoKeys = [
        revenueCatAPIKeyInfoKey,
        revenueCatTestAPIKeyInfoKey,
        superwallAPIKeyInfoKey
    ]

    let revenueCatAPIKey: String?
    let revenueCatAppStoreAPIKey: String?
    let revenueCatTestAPIKey: String?
    let superwallAPIKey: String?
    let revenueCatEntitlementID: String
    let revenueCatOfferingID: String
    let revenueCatYearlyProductID: String
    let revenueCatMonthlyProductID: String
    let isRevenueCatTestStoreEnabled: Bool
    let isSuperwallTestModeEnabled: Bool
    let allowsUnentitledAppAccess: Bool
    let auditsLaunchOffering: Bool
    let hasUnreplacedPlaceholderKeys: Bool

    var revenueCatStoreMode: RevenueCatStoreMode {
        guard let revenueCatAPIKey else { return .unavailable }
        return revenueCatAPIKey.hasPrefix("test_") ? .testStore : .appStore
    }

    var canConfigureRevenueCat: Bool {
        revenueCatAPIKey != nil
    }

    var canConfigureSuperwall: Bool {
        revenueCatAPIKey != nil && superwallAPIKey != nil
    }

    var launchProductIDs: [String] {
        [revenueCatYearlyProductID, revenueCatMonthlyProductID]
    }

    /// The launch product IDs are hardcoded to the production catalog, but Staging
    /// sells `ascend_staging_*`, so auditing there would emit
    /// `monetization_offering_mismatch` on every launch and drown the production
    /// signal the event exists to carry. Follow-up
    /// `ascend-unentitled-access-build-setting` makes the product IDs configurable
    /// per environment and restores this audit for Staging.
    var shouldAuditLaunchOffering: Bool {
        auditsLaunchOffering && revenueCatStoreMode == .appStore
    }

    func auditOffering(
        expectedOfferingProductIDs: Set<String>?,
        currentOfferingID: String?
    ) -> MonetizationOfferingAudit {
        let productIDs = expectedOfferingProductIDs ?? []

        return MonetizationOfferingAudit(
            expectedOfferingID: revenueCatOfferingID,
            currentOfferingID: currentOfferingID,
            hasExpectedOffering: expectedOfferingProductIDs != nil,
            missingProductIDs: launchProductIDs.filter { !productIDs.contains($0) }
        )
    }

    init(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        revenueCatEntitlementID: String = "app_access",
        revenueCatOfferingID: String = "default",
        revenueCatYearlyProductID: String = "ascend_yearly",
        revenueCatMonthlyProductID: String = "ascend_monthly",
        allowsTestMode: Bool = Self.defaultAllowsTestMode,
        allowsUnentitledAppAccess: Bool = Self.defaultAllowsUnentitledAppAccess,
        auditsLaunchOffering: Bool = Self.defaultAuditsLaunchOffering
    ) {
        let appStoreAPIKey = Self.normalizedAPIKey(infoDictionary[Self.revenueCatAPIKeyInfoKey])
        let testAPIKey = Self.normalizedAPIKey(infoDictionary[Self.revenueCatTestAPIKeyInfoKey])
        let shouldUseRevenueCatTestStore = allowsTestMode
            && (Self.normalizedBool(infoDictionary[Self.revenueCatUseTestStoreInfoKey]) ?? false)
            && testAPIKey != nil

        revenueCatAppStoreAPIKey = appStoreAPIKey
        revenueCatTestAPIKey = testAPIKey
        revenueCatAPIKey = shouldUseRevenueCatTestStore ? testAPIKey : appStoreAPIKey
        superwallAPIKey = Self.normalizedAPIKey(infoDictionary[Self.superwallAPIKeyInfoKey])
        self.revenueCatEntitlementID = revenueCatEntitlementID
        self.revenueCatOfferingID = revenueCatOfferingID
        self.revenueCatYearlyProductID = revenueCatYearlyProductID
        self.revenueCatMonthlyProductID = revenueCatMonthlyProductID
        isRevenueCatTestStoreEnabled = shouldUseRevenueCatTestStore
        isSuperwallTestModeEnabled = allowsTestMode
            && (Self.normalizedBool(infoDictionary[Self.superwallTestModeInfoKey]) ?? false)
        self.allowsUnentitledAppAccess = allowsUnentitledAppAccess
        self.auditsLaunchOffering = auditsLaunchOffering
        hasUnreplacedPlaceholderKeys = Self.apiKeyInfoKeys.contains { infoKey in
            guard let rawValue = infoDictionary[infoKey] as? String else { return false }
            return Self.isPlaceholderAPIKey(rawValue)
        }
    }

    static func isPlaceholderAPIKey(_ value: String) -> Bool {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .hasPrefix(placeholderAPIKeyPrefix)
    }

    private static func normalizedAPIKey(_ value: Any?) -> String? {
        guard let rawValue = value as? String else { return nil }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              !trimmedValue.hasPrefix("$("),
              !Self.isPlaceholderAPIKey(trimmedValue) else {
            return nil
        }

        return trimmedValue
    }

    private static func normalizedBool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }

        guard let rawValue = value as? String else { return nil }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }

    private static var defaultAllowsTestMode: Bool {
        #if DEBUG || STAGING
        true
        #else
        false
        #endif
    }

    private static var defaultAllowsUnentitledAppAccess: Bool {
        #if DEBUG || STAGING
        true
        #else
        false
        #endif
    }

    private static var defaultAuditsLaunchOffering: Bool {
        #if DEBUG || STAGING
        false
        #else
        true
        #endif
    }
}
