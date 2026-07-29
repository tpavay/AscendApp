import Foundation
import Testing
@testable import AscendApp

struct MonetizationConfigurationTests {
    @Test
    func readsConfiguredAPIKeys() {
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: " appl_test_key ",
                MonetizationConfiguration.revenueCatTestAPIKeyInfoKey: " test_store_key ",
                MonetizationConfiguration.superwallAPIKeyInfoKey: " pk_test_key "
            ]
        )

        #expect(configuration.revenueCatAPIKey == "appl_test_key")
        #expect(configuration.revenueCatAppStoreAPIKey == "appl_test_key")
        #expect(configuration.revenueCatTestAPIKey == "test_store_key")
        #expect(configuration.superwallAPIKey == "pk_test_key")
        #expect(configuration.hasUnreplacedPlaceholderKeys == false)
    }

    @Test
    func treatsMissingAndUnresolvedKeysAsUnavailable() {
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "$(ASCEND_REVENUECAT_API_KEY)",
                MonetizationConfiguration.revenueCatTestAPIKeyInfoKey: "$(ASCEND_REVENUECAT_TEST_API_KEY)",
                MonetizationConfiguration.superwallAPIKeyInfoKey: ""
            ]
        )

        #expect(configuration.revenueCatAPIKey == nil)
        #expect(configuration.revenueCatTestAPIKey == nil)
        #expect(configuration.superwallAPIKey == nil)
        #expect(configuration.hasUnreplacedPlaceholderKeys == false)
    }

    @Test
    func treatsUnreplacedPlaceholderKeysAsUnavailable() {
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "REPLACE_ME_PRODUCTION_REVENUECAT_KEY",
                MonetizationConfiguration.revenueCatTestAPIKeyInfoKey: " replace_me_production_revenuecat_test_key ",
                MonetizationConfiguration.revenueCatUseTestStoreInfoKey: "YES",
                MonetizationConfiguration.superwallAPIKeyInfoKey: "REPLACE_ME_PRODUCTION_SUPERWALL_KEY",
                MonetizationConfiguration.superwallTestModeInfoKey: "YES",
                MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
            ],
            allowsRevenueCatTestStore: true
        )

        #expect(configuration.revenueCatAPIKey == nil)
        #expect(configuration.revenueCatAppStoreAPIKey == nil)
        #expect(configuration.revenueCatTestAPIKey == nil)
        #expect(configuration.superwallAPIKey == nil)
        #expect(configuration.revenueCatStoreMode == .unavailable)
        #expect(configuration.isRevenueCatTestStoreEnabled == false)
        #expect(configuration.canConfigureRevenueCat == false)
        #expect(configuration.canConfigureSuperwall == false)
        #expect(configuration.hasUnreplacedPlaceholderKeys)
    }

    @Test
    func flagsPlaceholdersEvenWhenOnlyOneKeyIsUnreplaced() {
        let superwallPlaceholderOnly = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test_key",
                MonetizationConfiguration.superwallAPIKeyInfoKey: "REPLACE_ME_STAGING_SUPERWALL_KEY"
            ]
        )

        #expect(superwallPlaceholderOnly.revenueCatAPIKey == "appl_test_key")
        #expect(superwallPlaceholderOnly.superwallAPIKey == nil)
        #expect(superwallPlaceholderOnly.canConfigureRevenueCat)
        #expect(superwallPlaceholderOnly.canConfigureSuperwall == false)
        #expect(superwallPlaceholderOnly.hasUnreplacedPlaceholderKeys)
    }

    @Test
    func exposesConfigurationAvailability() {
        let revenueCatOnly = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test_key"
            ]
        )
        let fullyConfigured = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test_key",
                MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test_key"
            ]
        )

        #expect(revenueCatOnly.canConfigureRevenueCat)
        #expect(revenueCatOnly.canConfigureSuperwall == false)
        #expect(fullyConfigured.canConfigureRevenueCat)
        #expect(fullyConfigured.canConfigureSuperwall)
    }

    @Test
    func enablesDebugTestModesWhenExplicitlyAllowed() {
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test_key",
                MonetizationConfiguration.revenueCatTestAPIKeyInfoKey: "test_store_key",
                MonetizationConfiguration.revenueCatUseTestStoreInfoKey: "YES",
                MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test_key",
                MonetizationConfiguration.superwallTestModeInfoKey: "true"
            ],
            allowsRevenueCatTestStore: true
        )

        #expect(configuration.revenueCatAPIKey == "test_store_key")
        #expect(configuration.revenueCatStoreMode == .testStore)
        #expect(configuration.isRevenueCatTestStoreEnabled)
        #expect(configuration.isSuperwallTestModeEnabled)
    }

    @Test
    func keepsRevenueCatTestStoreDisabledButHonorsSuperwallTestModeSetting() {
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test_key",
                MonetizationConfiguration.revenueCatTestAPIKeyInfoKey: "test_store_key",
                MonetizationConfiguration.revenueCatUseTestStoreInfoKey: "YES",
                MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test_key",
                MonetizationConfiguration.superwallTestModeInfoKey: "true"
            ],
            allowsRevenueCatTestStore: false
        )

        #expect(configuration.revenueCatAPIKey == "appl_test_key")
        #expect(configuration.revenueCatStoreMode == .appStore)
        #expect(configuration.isRevenueCatTestStoreEnabled == false)
        #expect(configuration.isSuperwallTestModeEnabled)
    }

    @Test
    func readsUnentitledAccessBypassFromInfoDictionaryAndFailsClosed() {
        let gated = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
            ]
        )
        let bypassed = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "YES"
            ]
        )
        let missing = MonetizationConfiguration(infoDictionary: [:])
        let malformed = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "sometimes"
            ]
        )

        #expect(gated.allowsUnentitledAppAccess == false)
        #expect(bypassed.allowsUnentitledAppAccess)
        #expect(missing.allowsUnentitledAppAccess == false)
        #expect(malformed.allowsUnentitledAppAccess == false)
    }

    @Test
    func keepsStableAccessIdentifiers() {
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "ascend_yearly",
                MonetizationConfiguration.revenueCatMonthlyProductIDInfoKey: "ascend_monthly"
            ]
        )

        #expect(configuration.revenueCatEntitlementID == "app_access")
        #expect(configuration.revenueCatOfferingID == "default")
        #expect(configuration.revenueCatYearlyProductID == "ascend_yearly")
        #expect(configuration.revenueCatMonthlyProductID == "ascend_monthly")
        #expect(SuperwallPlacement.onboardingPaywall.rawValue == "onboarding_paywall")
        #expect(SuperwallPlacement.appLaunchHardGate.rawValue == "app_launch_hard_gate")
        #expect(SuperwallPlacement.appAccessGate.rawValue == "app_access_gate")
    }

    @Test
    func auditsTheConfiguredStagingLaunchCatalogAndDetectsAGenuineMismatch() {
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_staging_key",
                MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "ascend_staging_yearly",
                MonetizationConfiguration.revenueCatMonthlyProductIDInfoKey: "ascend_staging_monthly"
            ]
        )

        let complete = configuration.auditOffering(
            expectedOfferingProductIDs: ["ascend_staging_yearly", "ascend_staging_monthly"],
            currentOfferingID: "default"
        )
        let missingMonthly = configuration.auditOffering(
            expectedOfferingProductIDs: ["ascend_staging_yearly"],
            currentOfferingID: "default"
        )
        let missingOffering = configuration.auditOffering(
            expectedOfferingProductIDs: nil,
            currentOfferingID: nil
        )

        #expect(configuration.shouldAuditLaunchOffering)
        #expect(complete.isLaunchCatalogComplete)
        #expect(complete.missingProductIDs.isEmpty)
        #expect(missingMonthly.isLaunchCatalogComplete == false)
        #expect(missingMonthly.missingProductIDs == ["ascend_staging_monthly"])
        #expect(missingOffering.isLaunchCatalogComplete == false)
        #expect(missingOffering.hasExpectedOffering == false)
        #expect(
            missingOffering.missingProductIDs
                == ["ascend_staging_yearly", "ascend_staging_monthly"]
        )
    }

    @Test
    func auditsEveryConfiguredAppStoreEnvironment() {
        let staging = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_staging_key",
                MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "ascend_staging_yearly",
                MonetizationConfiguration.revenueCatMonthlyProductIDInfoKey: "ascend_staging_monthly"
            ]
        )
        let release = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_production_key",
                MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "ascend_yearly",
                MonetizationConfiguration.revenueCatMonthlyProductIDInfoKey: "ascend_monthly"
            ]
        )

        #expect(staging.revenueCatStoreMode == .appStore)
        #expect(release.revenueCatStoreMode == .appStore)
        #expect(staging.shouldAuditLaunchOffering)
        #expect(release.shouldAuditLaunchOffering)
    }

    @Test
    func missingLaunchProductSettingsCannotPassTheAudit() {
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_staging_key"
            ]
        )

        let audit = configuration.auditOffering(
            expectedOfferingProductIDs: ["ascend_staging_yearly", "ascend_staging_monthly"],
            currentOfferingID: "default"
        )

        #expect(configuration.shouldAuditLaunchOffering)
        #expect(audit.isLaunchCatalogComplete == false)
        #expect(audit.missingProductIDs.count == 2)
        #expect(
            audit.missingProductIDs.allSatisfy {
                $0.hasPrefix("UNCONFIGURED_ASCEND_REVENUECAT_")
            }
        )
    }

    @Test
    func keepsTheLaunchCatalogAuditFullyEnforcedInRelease() {
        let release = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_production_key",
                MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "ascend_yearly",
                MonetizationConfiguration.revenueCatMonthlyProductIDInfoKey: "ascend_monthly"
            ],
            allowsRevenueCatTestStore: false
        )

        #expect(release.shouldAuditLaunchOffering)

        let audit = release.auditOffering(
            expectedOfferingProductIDs: ["ascend_yearly"],
            currentOfferingID: "default"
        )

        #expect(audit.isLaunchCatalogComplete == false)
        #expect(audit.missingProductIDs == ["ascend_monthly"])
    }

    @Test
    func suppressesTheLaunchOfferingAuditWithoutAnAppStoreKey() {
        let testStore = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test_key",
                MonetizationConfiguration.revenueCatTestAPIKeyInfoKey: "test_store_key",
                MonetizationConfiguration.revenueCatUseTestStoreInfoKey: "YES"
            ],
            allowsRevenueCatTestStore: true
        )
        let unavailable = MonetizationConfiguration(infoDictionary: [:])

        #expect(testStore.revenueCatStoreMode == .testStore)
        #expect(testStore.shouldAuditLaunchOffering == false)
        #expect(unavailable.revenueCatStoreMode == .unavailable)
        #expect(unavailable.shouldAuditLaunchOffering == false)
    }

    @Test
    func treatsAnExperimentOfferingAsAServingChoiceRatherThanABrokenCatalog() {
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "ascend_yearly",
                MonetizationConfiguration.revenueCatMonthlyProductIDInfoKey: "ascend_monthly"
            ]
        )

        let experiment = configuration.auditOffering(
            expectedOfferingProductIDs: ["ascend_yearly", "ascend_monthly"],
            currentOfferingID: "launch_test_b"
        )

        #expect(experiment.isLaunchCatalogComplete)
        #expect(experiment.isServingExpectedOffering == false)
        #expect(experiment.currentOfferingID == "launch_test_b")
    }
}
