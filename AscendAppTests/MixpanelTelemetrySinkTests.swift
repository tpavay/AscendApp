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
                infoDictionary: [AnalyticsConfiguration.mixpanelTokenInfoKey: "token"]
            ),
            buildMetadata: buildMetadata,
            makeClient: { _, _ in client }
        )
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true
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
    }

    @Test
    func restoresBuildMetadataAfterIdentityReset() {
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
                infoDictionary: [AnalyticsConfiguration.mixpanelTokenInfoKey: "token"]
            ),
            buildMetadata: buildMetadata,
            makeClient: { _, _ in client }
        )

        sink.setUserID(nil)
        sink.record(TelemetryRecord(name: "signed_out_event"))

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
                infoDictionary: [AnalyticsConfiguration.mixpanelTokenInfoKey: "token"]
            ),
            buildMetadata: buildMetadata,
            makeClient: { _, _ in client }
        )

        sink.setUserProperty("app_environment", value: "spoofed")

        #expect(client.calls == ["register_super_properties", "set_user_property", "register_super_properties"])
        #expect(client.registeredSuperProperties == buildMetadata.properties)
    }
}

private extension MixpanelTelemetrySinkTests {
    final class RecordingMixpanelClient: MixpanelClient {
        var loggingEnabled = false
        private(set) var calls: [String] = []
        private(set) var registeredSuperProperties: [String: String] = [:]
        private(set) var trackedEvents: [String] = []

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
        }

        func flush(performFullFlush: Bool) {}
    }
}
