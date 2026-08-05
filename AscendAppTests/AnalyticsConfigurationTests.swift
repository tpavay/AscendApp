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
    func destinationMustMatchTheCompiledEnvironment() throws {
        let configuration = AnalyticsConfiguration(
            infoDictionary: [
                AnalyticsConfiguration.mixpanelTokenInfoKey: "token",
                AnalyticsConfiguration.mixpanelProjectIDInfoKey: "4051100"
            ]
        )
        let staging = try TelemetryEnvelope(
            validating: TelemetryBuildMetadata(
                appEnvironment: "staging",
                buildConfig: "staging",
                appVersion: "1.2.3",
                buildNumber: "456",
                bundleIdentifier: "com.tylerpavay.AscendApp.staging"
            )
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

    /// The Swift environment-to-project map, the pbxproj build settings, and the
    /// Node contract are three files that must agree; this proves the compiled
    /// bundle resolves a destination for the configuration it was compiled as.
    /// Nothing here reads or reports the token value.
    @Test
    func compiledBundleResolvesADestinationForItsOwnEnvironment() throws {
        let envelope = try TelemetryEnvelope(validating: .current)
        let resolvedADestination = try AnalyticsConfiguration.live
            .validatedMixpanelToken(for: envelope) != nil

        #expect(resolvedADestination)
    }
}
