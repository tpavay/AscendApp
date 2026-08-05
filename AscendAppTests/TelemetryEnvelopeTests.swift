import Testing
@testable import AscendApp

struct TelemetryEnvelopeTests {
    @Test
    func acceptsOnlyTheThreeBuildEnvironmentPairs() throws {
        let pairs = [
            (appEnvironment: "dev", buildConfig: "debug"),
            (appEnvironment: "staging", buildConfig: "staging"),
            (appEnvironment: "production", buildConfig: "release")
        ]

        for pair in pairs {
            let envelope = try TelemetryEnvelope(
                validating: metadata(
                    appEnvironment: pair.appEnvironment,
                    buildConfig: pair.buildConfig
                )
            )

            #expect(envelope.appEnvironment == pair.appEnvironment)
            #expect(envelope.buildConfig == pair.buildConfig)
            #expect(envelope.properties.count == 4)
        }
    }

    @Test
    func rejectsAnEnvironmentThatDisagreesWithTheBuildConfiguration() {
        do {
            _ = try TelemetryEnvelope(
                validating: metadata(appEnvironment: "production", buildConfig: "debug")
            )
            Issue.record("A mismatched environment and build configuration must be rejected.")
        } catch TelemetryEnvelope.ValidationError.inconsistentEnvironment {
            // Expected.
        } catch {
            Issue.record("Unexpected validation error: \(error)")
        }
    }

    @Test
    func rejectsMissingBundleVersionFields() {
        do {
            _ = try TelemetryEnvelope(
                validating: metadata(appVersion: "")
            )
            Issue.record("A missing app version must be rejected.")
        } catch TelemetryEnvelope.ValidationError.missingAppVersion {
            // Expected.
        } catch {
            Issue.record("Unexpected app-version validation error: \(error)")
        }

        do {
            _ = try TelemetryEnvelope(
                validating: metadata(buildNumber: "")
            )
            Issue.record("A missing build number must be rejected.")
        } catch TelemetryEnvelope.ValidationError.missingBuildNumber {
            // Expected.
        } catch {
            Issue.record("Unexpected build-number validation error: \(error)")
        }
    }

    /// `MixpanelTelemetrySink.accepts(_:)` gates on the resolving envelope being
    /// equal to the validating one, so any normalization the two initializers
    /// disagree on would silently drop every Mixpanel event.
    @Test
    func bothInitializersNormalizeSurroundingWhitespaceIdentically() throws {
        let padded = metadata(appVersion: " 1.2.3 ", buildNumber: "\t456\n")

        let resolved = TelemetryEnvelope(resolving: padded)
        let validated = try TelemetryEnvelope(validating: padded)

        #expect(resolved == validated)
        #expect(validated.appVersion == "1.2.3")
        #expect(validated.buildNumber == "456")
        #expect(resolved.appVersion == "1.2.3")
        #expect(resolved.buildNumber == "456")
    }
}

private extension TelemetryEnvelopeTests {
    func metadata(
        appEnvironment: String = "staging",
        buildConfig: String = "staging",
        appVersion: String = "1.2.3",
        buildNumber: String = "456"
    ) -> TelemetryBuildMetadata {
        TelemetryBuildMetadata(
            appEnvironment: appEnvironment,
            buildConfig: buildConfig,
            appVersion: appVersion,
            buildNumber: buildNumber,
            bundleIdentifier: "com.tylerpavay.AscendApp.tests"
        )
    }
}
