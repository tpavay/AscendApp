import Testing
@testable import AscendApp

struct AnalyticsConfigurationTests {
    @Test
    func mixpanelTokenIgnoresUnexpandedBuildSettingPlaceholder() {
        let configuration = AnalyticsConfiguration(
            infoDictionary: [
                AnalyticsConfiguration.mixpanelTokenInfoKey: "$(ASCEND_MIXPANEL_TOKEN)"
            ]
        )

        #expect(configuration.mixpanelToken == nil)
        #expect(!configuration.canConfigureMixpanel)
    }

    @Test
    func mixpanelTokenTrimsConfiguredValue() {
        let configuration = AnalyticsConfiguration(
            infoDictionary: [
                AnalyticsConfiguration.mixpanelTokenInfoKey: " token-123 "
            ]
        )

        #expect(configuration.mixpanelToken == "token-123")
        #expect(configuration.canConfigureMixpanel)
    }
}
