import Mixpanel
import Testing
@testable import AscendApp

struct MixpanelTelemetrySinkTests {
    @Test
    func registersBuildMetadataBeforeFirstEvent() {
        let client = RecordingMixpanelClient()
        let buildMetadata = TelemetryBuildMetadata(
            appEnvironment: "staging",
            buildConfig: "staging",
            appVersion: "1.2.3",
            buildNumber: "456",
            bundleIdentifier: "com.tylerpavay.AscendApp.staging"
        )
        let sink = MixpanelTelemetrySink(
            configuration: AnalyticsConfiguration(
                infoDictionary: [
                    AnalyticsConfiguration.mixpanelTokenInfoKey: "token",
                    AnalyticsConfiguration.mixpanelProjectIDInfoKey: "4051102"
                ]
            ),
            buildMetadata: buildMetadata,
            makeClient: { _, _ in client }
        )
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            buildMetadata: buildMetadata
        )

        telemetry.configure()
        telemetry.track(TelemetryRecord(name: "first_event"))

        #expect(
            client.calls == [
                "register_super_properties",
                "register_super_properties",
                "opt_in",
                "track"
            ]
        )
        #expect(client.registeredSuperProperties == buildMetadata.properties)
        #expect(client.trackedEvents == ["first_event"])
        let trackedProperties = client.trackedProperties.first
        let appEnvironment = trackedProperties?["app_environment"] as? String
        let buildConfig = trackedProperties?["build_config"] as? String
        let appVersion = trackedProperties?["app_version"] as? String
        let buildNumber = trackedProperties?["build_number"] as? String
        #expect(appEnvironment == "staging")
        #expect(buildConfig == "staging")
        #expect(appVersion == "1.2.3")
        #expect(buildNumber == "456")
    }

    @Test
    func restoresBuildMetadataAfterIdentityReset() throws {
        let client = RecordingMixpanelClient()
        let buildMetadata = TelemetryBuildMetadata(
            appEnvironment: "production",
            buildConfig: "release",
            appVersion: "1.2.3",
            buildNumber: "456",
            bundleIdentifier: "com.tylerpavay.AscendApp"
        )
        let sink = MixpanelTelemetrySink(
            configuration: AnalyticsConfiguration(
                infoDictionary: [
                    AnalyticsConfiguration.mixpanelTokenInfoKey: "token",
                    AnalyticsConfiguration.mixpanelProjectIDInfoKey: "4051100"
                ]
            ),
            buildMetadata: buildMetadata,
            makeClient: { _, _ in client }
        )

        sink.setUserID(nil)
        sink.record(
            EnvelopedTelemetryRecord(
                record: TelemetryRecord(name: "signed_out_event"),
                envelope: try TelemetryEnvelope(validating: buildMetadata)
            )
        )

        #expect(client.calls == ["register_super_properties", "reset", "register_super_properties", "track"])
        #expect(client.registeredSuperProperties == buildMetadata.properties)
        #expect(client.trackedEvents == ["signed_out_event"])
    }

    @Test
    func restoresBuildMetadataWhenUserPropertyCollidesWithReservedKey() {
        let client = RecordingMixpanelClient()
        let buildMetadata = TelemetryBuildMetadata(
            appEnvironment: "staging",
            buildConfig: "staging",
            appVersion: "1.2.3",
            buildNumber: "456",
            bundleIdentifier: "com.tylerpavay.AscendApp.staging"
        )
        let sink = MixpanelTelemetrySink(
            configuration: AnalyticsConfiguration(
                infoDictionary: [
                    AnalyticsConfiguration.mixpanelTokenInfoKey: "token",
                    AnalyticsConfiguration.mixpanelProjectIDInfoKey: "4051102"
                ]
            ),
            buildMetadata: buildMetadata,
            makeClient: { _, _ in client }
        )

        sink.setUserProperty("app_environment", value: "spoofed")

        #expect(client.calls == ["register_super_properties", "set_user_property", "register_super_properties"])
        #expect(client.registeredSuperProperties == buildMetadata.properties)
    }

    #if !DEBUG
    /// Shipping builds must degrade analytics, never terminate: the trap that
    /// catches destination drift is a DEBUG-only development aid.
    @Test
    func aShippingBuildGoesSilentInsteadOfTrappingOnDestinationDrift() throws {
        let mismatchedClient = RecordingMixpanelClient()
        let mismatchedDestination = MixpanelTelemetrySink(
            configuration: AnalyticsConfiguration(
                infoDictionary: [
                    AnalyticsConfiguration.mixpanelTokenInfoKey: "token",
                    AnalyticsConfiguration.mixpanelProjectIDInfoKey: "4051100"
                ]
            ),
            buildMetadata: Self.stagingBuildMetadata,
            makeClient: { _, _ in mismatchedClient }
        )

        let unvalidatableClient = RecordingMixpanelClient()
        let unvalidatableEnvelope = MixpanelTelemetrySink(
            configuration: AnalyticsConfiguration(
                infoDictionary: [
                    AnalyticsConfiguration.mixpanelTokenInfoKey: "token",
                    AnalyticsConfiguration.mixpanelProjectIDInfoKey: "4051102"
                ]
            ),
            buildMetadata: TelemetryBuildMetadata(
                appEnvironment: "staging",
                buildConfig: "staging",
                appVersion: "",
                buildNumber: "",
                bundleIdentifier: "com.tylerpavay.AscendApp.staging"
            ),
            makeClient: { _, _ in unvalidatableClient }
        )

        let record = EnvelopedTelemetryRecord(
            record: TelemetryRecord(name: "dropped_event"),
            envelope: try TelemetryEnvelope(validating: Self.stagingBuildMetadata)
        )

        mismatchedDestination.setCollectionEnabled(true)
        mismatchedDestination.record(record)
        unvalidatableEnvelope.setCollectionEnabled(true)
        unvalidatableEnvelope.record(record)

        #expect(mismatchedClient.calls.isEmpty)
        #expect(unvalidatableClient.calls.isEmpty)
    }
    #endif

    private static let stagingBuildMetadata = TelemetryBuildMetadata(
        appEnvironment: "staging",
        buildConfig: "staging",
        appVersion: "1.2.3",
        buildNumber: "456",
        bundleIdentifier: "com.tylerpavay.AscendApp.staging"
    )
}

private extension MixpanelTelemetrySinkTests {
    final class RecordingMixpanelClient: MixpanelClient {
        var loggingEnabled = false
        private(set) var calls: [String] = []
        private(set) var registeredSuperProperties: [String: String] = [:]
        private(set) var trackedEvents: [String] = []
        private(set) var trackedProperties: [Properties] = []

        func setCollectionEnabled(_ enabled: Bool) {
            calls.append(enabled ? "opt_in" : "opt_out")
            if !enabled {
                registeredSuperProperties.removeAll()
            }
        }

        func setUserID(_ userID: String?) {
            calls.append(userID == nil ? "reset" : "identify")
            if userID == nil {
                registeredSuperProperties.removeAll()
            }
        }

        func setUserProperty(_ name: String, value: String?) {
            calls.append("set_user_property")
            registeredSuperProperties[name] = value
        }

        func registerSuperProperties(_ properties: [String: String]) {
            calls.append("register_super_properties")
            registeredSuperProperties.merge(properties) { _, registered in registered }
        }

        func track(event: String, properties: Properties) {
            calls.append("track")
            trackedEvents.append(event)
            trackedProperties.append(properties)
        }

        func flush(performFullFlush: Bool) {}
    }
}
