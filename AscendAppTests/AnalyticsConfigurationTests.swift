import Testing
@testable import AscendApp

struct AnalyticsConfigurationTests {
    @Test
    func mixpanelTokenIgnoresUnexpandedBuildSettingPlaceholder() {
        let configuration = AnalyticsConfiguration(
            infoDictionary: [
                AnalyticsConfiguration.mixpanelTokenInfoKey: "$(ASCEND_MIXPANEL_TOKEN)",
                AnalyticsConfiguration.mixpanelProjectIDInfoKey: "$(ASCEND_MIXPANEL_PROJECT_ID)"
            ]
        )

        #expect(configuration.mixpanelToken == nil)
        #expect(configuration.canConfigureMixpanel == false)
    }

    @Test
    func mixpanelTokenTrimsConfiguredValue() {
        let configuration = AnalyticsConfiguration(
            infoDictionary: [
                AnalyticsConfiguration.mixpanelTokenInfoKey: " token-123 ",
                AnalyticsConfiguration.mixpanelProjectIDInfoKey: " 4051102 "
            ]
        )

        #expect(configuration.mixpanelToken == "token-123")
        #expect(configuration.mixpanelProjectID == "4051102")
        #expect(configuration.canConfigureMixpanel)
    }

    @Test
    func destinationMustMatchTheCompiledEnvironment() {
        let configuration = AnalyticsConfiguration(
            infoDictionary: [
                AnalyticsConfiguration.mixpanelTokenInfoKey: "token",
                AnalyticsConfiguration.mixpanelProjectIDInfoKey: "4051100"
            ]
        )
        let staging = TelemetryBuildMetadata(
            appEnvironment: "staging",
            buildConfig: "staging",
            appVersion: "1.2.3",
            buildNumber: "456",
            bundleIdentifier: "com.tylerpavay.AscendApp.staging"
        )

        do {
            _ = try configuration.validatedMixpanelToken(for: staging)
            Issue.record("A Staging build must reject the Production Mixpanel project.")
        } catch AnalyticsConfiguration.ValidationError.environmentProjectMismatch {
            // Expected.
        } catch {
            Issue.record("Unexpected validation error: \(error)")
        }
    }
}
