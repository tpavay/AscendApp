import Foundation
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
    ///
    /// The runtime is pinned to a device so the assertion stays about the destination map. Where
    /// the tests happen to run is the subject of `productionIsUnreachableFromASimulator`.
    @Test
    func compiledBundleResolvesADestinationForItsOwnEnvironment() throws {
        let envelope = try TelemetryEnvelope(validating: .current)
        let resolvedADestination = try AnalyticsConfiguration.live.validatedMixpanelToken(
            for: envelope,
            runtime: TelemetryRuntimeEnvironment(isSimulator: false)
        ) != nil

        #expect(resolvedADestination)
    }

    /// A Release binary compiled for the simulator SDK reports `production` / `release` exactly
    /// like a customer's build, so the environment-to-project map alone cannot stop it: 34
    /// simulator identities and 167 events reached production this way, and `$model == "arm64"`
    /// was the only thing that could tell them apart afterwards.
    @Test
    func productionIsUnreachableFromASimulator() throws {
        let configuration = AnalyticsConfiguration(
            infoDictionary: [
                AnalyticsConfiguration.mixpanelTokenInfoKey: "token",
                AnalyticsConfiguration.mixpanelProjectIDInfoKey: "4051100"
            ]
        )
        let production = try TelemetryEnvelope(validating: Self.productionBuildMetadata)

        do {
            _ = try configuration.validatedMixpanelToken(
                for: production,
                runtime: TelemetryRuntimeEnvironment(isSimulator: true)
            )
            Issue.record("A simulator must never resolve the Production Mixpanel destination.")
        } catch AnalyticsConfiguration.ValidationError.simulatorCannotReachProduction {
            // Expected.
        } catch {
            Issue.record("Unexpected validation error: \(error)")
        }

        let onADevice = try configuration.validatedMixpanelToken(
            for: production,
            runtime: TelemetryRuntimeEnvironment(isSimulator: false)
        )
        #expect(onADevice != nil)
    }

    /// Staging is where a session is reproduced and a bug is recreated, so a simulator reaching it
    /// is the intended workflow, not the defect.
    @Test
    func aSimulatorStillReachesStaging() throws {
        let configuration = AnalyticsConfiguration(
            infoDictionary: [
                AnalyticsConfiguration.mixpanelTokenInfoKey: "token",
                AnalyticsConfiguration.mixpanelProjectIDInfoKey: "4051102"
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

        let resolved = try configuration.validatedMixpanelToken(
            for: staging,
            runtime: TelemetryRuntimeEnvironment(isSimulator: true)
        )

        #expect(resolved != nil)
    }

    /// Two independent answers, because either alone can be wrong in the direction that costs
    /// production data - and the process variables are what catch a device-SDK binary that
    /// simulator tooling launched anyway.
    @Test
    func theRuntimeReadsSimulatorProcessVariablesAsWellAsTheCompiledTarget() {
        let launchedBySimulatorTooling = TelemetryRuntimeEnvironment(
            processEnvironment: ["SIMULATOR_UDID": UUID().uuidString]
        )
        let bareProcess = TelemetryRuntimeEnvironment(processEnvironment: [:])

        #expect(launchedBySimulatorTooling.isSimulator)
        #expect(bareProcess.isSimulator == TelemetryRuntimeEnvironment.isCompiledForSimulator)
    }

    private static let productionBuildMetadata = TelemetryBuildMetadata(
        appEnvironment: "production",
        buildConfig: "release",
        appVersion: "1.0",
        buildNumber: "2026082101",
        bundleIdentifier: "com.tylerpavay.AscendApp"
    )
}
