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
        #expect(!configuration.hasUnreplacedPlaceholderKeys)
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
        #expect(!configuration.hasUnreplacedPlaceholderKeys)
    }

    @Test
    func treatsUnreplacedPlaceholderKeysAsUnavailable() {
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "REPLACE_ME_PRODUCTION_REVENUECAT_KEY",
                MonetizationConfiguration.revenueCatTestAPIKeyInfoKey: " replace_me_production_revenuecat_test_key ",
                MonetizationConfiguration.revenueCatUseTestStoreInfoKey: "YES",
                MonetizationConfiguration.superwallAPIKeyInfoKey: "REPLACE_ME_PRODUCTION_SUPERWALL_KEY",
                MonetizationConfiguration.superwallTestModeInfoKey: "YES"
            ],
            allowsTestMode: true,
            allowsUnentitledAppAccess: false
        )

        #expect(configuration.revenueCatAPIKey == nil)
        #expect(configuration.revenueCatAppStoreAPIKey == nil)
        #expect(configuration.revenueCatTestAPIKey == nil)
        #expect(configuration.superwallAPIKey == nil)
        #expect(configuration.revenueCatStoreMode == .unavailable)
        #expect(!configuration.isRevenueCatTestStoreEnabled)
        #expect(!configuration.canConfigureRevenueCat)
        #expect(!configuration.canConfigureSuperwall)
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
        #expect(!superwallPlaceholderOnly.canConfigureSuperwall)
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
        #expect(!revenueCatOnly.canConfigureSuperwall)
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
            allowsTestMode: true
        )

        #expect(configuration.revenueCatAPIKey == "test_store_key")
        #expect(configuration.revenueCatStoreMode == .testStore)
        #expect(configuration.isRevenueCatTestStoreEnabled)
        #expect(configuration.isSuperwallTestModeEnabled)
    }

    @Test
    func ignoresTestModesWhenNotAllowed() {
        let configuration = MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test_key",
                MonetizationConfiguration.revenueCatTestAPIKeyInfoKey: "test_store_key",
                MonetizationConfiguration.revenueCatUseTestStoreInfoKey: "YES",
                MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test_key",
                MonetizationConfiguration.superwallTestModeInfoKey: "true"
            ],
            allowsTestMode: false
        )

        #expect(configuration.revenueCatAPIKey == "appl_test_key")
        #expect(configuration.revenueCatStoreMode == .appStore)
        #expect(!configuration.isRevenueCatTestStoreEnabled)
        #expect(!configuration.isSuperwallTestModeEnabled)
    }

    @Test
    func exposesUnentitledAccessBypassConfiguration() {
        let gated = MonetizationConfiguration(
            infoDictionary: [:],
            allowsUnentitledAppAccess: false
        )
        let bypassed = MonetizationConfiguration(
            infoDictionary: [:],
            allowsUnentitledAppAccess: true
        )

        #expect(!gated.allowsUnentitledAppAccess)
        #expect(bypassed.allowsUnentitledAppAccess)
    }

    @Test
    func keepsStableAccessIdentifiers() {
        let configuration = MonetizationConfiguration(infoDictionary: [:])

        #expect(configuration.revenueCatEntitlementID == "app_access")
        #expect(configuration.revenueCatOfferingID == "default")
        #expect(configuration.revenueCatYearlyProductID == "ascend_yearly")
        #expect(configuration.revenueCatMonthlyProductID == "ascend_monthly")
        #expect(SuperwallPlacement.onboardingPaywall.rawValue == "onboarding_paywall")
        #expect(SuperwallPlacement.appLaunchHardGate.rawValue == "app_launch_hard_gate")
        #expect(SuperwallPlacement.appAccessGate.rawValue == "app_access_gate")
    }

    @Test
    func flagsALaunchCatalogThatDoesNotMatchTheContract() {
        let configuration = MonetizationConfiguration(infoDictionary: [:])

        let complete = configuration.auditOffering(
            expectedOfferingProductIDs: ["ascend_yearly", "ascend_monthly"],
            currentOfferingID: "default"
        )
        let missingMonthly = configuration.auditOffering(
            expectedOfferingProductIDs: ["ascend_yearly"],
            currentOfferingID: "default"
        )
        let missingOffering = configuration.auditOffering(
            expectedOfferingProductIDs: nil,
            currentOfferingID: nil
        )

        #expect(complete.isLaunchCatalogComplete)
        #expect(complete.missingProductIDs.isEmpty)
        #expect(!missingMonthly.isLaunchCatalogComplete)
        #expect(missingMonthly.missingProductIDs == ["ascend_monthly"])
        #expect(!missingOffering.isLaunchCatalogComplete)
        #expect(!missingOffering.hasExpectedOffering)
        #expect(missingOffering.missingProductIDs == ["ascend_yearly", "ascend_monthly"])
    }

    @Test
    func treatsAnExperimentOfferingAsAServingChoiceRatherThanABrokenCatalog() {
        let configuration = MonetizationConfiguration(infoDictionary: [:])

        let experiment = configuration.auditOffering(
            expectedOfferingProductIDs: ["ascend_yearly", "ascend_monthly"],
            currentOfferingID: "launch_test_b"
        )

        #expect(experiment.isLaunchCatalogComplete)
        #expect(!experiment.isServingExpectedOffering)
        #expect(experiment.currentOfferingID == "launch_test_b")
    }
}
