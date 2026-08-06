import Foundation
@preconcurrency import Mixpanel

final class MixpanelTelemetrySink: TelemetrySink, @unchecked Sendable {
    let supportedDestinations: Set<TelemetryDestination> = [.analytics]

    private let configuration: AnalyticsConfiguration
    private let buildMetadata: TelemetryBuildMetadata
    private let validatedEnvelope: TelemetryEnvelope?
    private let makeClient: (String, Double) -> any MixpanelClient
    private let lock = NSLock()
    private var client: (any MixpanelClient)?

    init(
        configuration: AnalyticsConfiguration = .live,
        buildMetadata: TelemetryBuildMetadata = .current,
        makeClient: @escaping (String, Double) -> any MixpanelClient = {
            MixpanelSDKClient(token: $0, flushInterval: $1)
        }
    ) {
        self.configuration = configuration
        self.buildMetadata = buildMetadata
        self.validatedEnvelope = try? TelemetryEnvelope(validating: buildMetadata)
        self.makeClient = makeClient
    }

    func setCollectionEnabled(_ enabled: Bool) {
        withConfiguredClient { client in
            if enabled {
                client.registerSuperProperties(buildMetadata.properties)
            }
            client.setCollectionEnabled(enabled)
        }
    }

    func setUserID(_ userID: String?) {
        withConfiguredClient { client in
            client.setUserID(userID)
            if userID == nil {
                client.registerSuperProperties(buildMetadata.properties)
            }
        }
    }

    func setUserProperty(_ name: String, value: String?) {
        withConfiguredClient { client in
            client.setUserProperty(name, value: value)
            // A caller can pass any name, including one of the reserved build-metadata
            // keys; the build's own values stay authoritative after such a collision.
            if buildMetadata.properties[name] != nil {
                client.registerSuperProperties(buildMetadata.properties)
            }
            flushAfterDebugEvent(client)
        }
    }

    func record(_ record: EnvelopedTelemetryRecord) {
        guard accepts(record.envelope) else { return }

        withConfiguredClient { client in
            client.track(
                event: record.name,
                properties: record.parameters.mixpanelProperties
            )
            flushAfterDebugEvent(client)
        }
    }

    func record(screen: EnvelopedTelemetryScreen) {
        guard accepts(screen.envelope) else { return }

        withConfiguredClient { client in
            var properties = screen.parameters.mixpanelProperties
            properties["screen_name"] = screen.name
            properties["screen_class"] = screen.screenClass

            client.track(
                event: "screen_view",
                properties: properties
            )
            flushAfterDebugEvent(client)
        }
    }

    private func withConfiguredClient(_ action: (any MixpanelClient) -> Void) {
        guard let token = validatedToken() else { return }

        lock.lock()
        defer { lock.unlock() }

        if let client {
            action(client)
            return
        }

        let client = makeClient(token, flushInterval)
        #if DEBUG
        client.loggingEnabled = true
        #endif
        client.registerSuperProperties(buildMetadata.properties)
        self.client = client
        action(client)
    }

    // Every guard below fails closed outside DEBUG: an analytics misconfiguration
    // must silence Mixpanel, never terminate a tester's or a customer's app.
    private func validatedToken() -> String? {
        guard let validatedEnvelope else {
            #if DEBUG
            preconditionFailure("Telemetry envelope is invalid for this build configuration.")
            #else
            return nil
            #endif
        }

        do {
            return try configuration.validatedMixpanelToken(for: validatedEnvelope)
        } catch {
            #if DEBUG
            preconditionFailure("Mixpanel destination does not match this build configuration.")
            #else
            return nil
            #endif
        }
    }

    private func accepts(_ envelope: TelemetryEnvelope) -> Bool {
        guard let validatedEnvelope, envelope == validatedEnvelope else {
            #if DEBUG
            preconditionFailure("Mixpanel received an envelope for a different build configuration.")
            #else
            return false
            #endif
        }

        return true
    }

    private var flushInterval: Double {
        #if DEBUG
        return 5
        #else
        return 60
        #endif
    }

    private func flushAfterDebugEvent(_ client: any MixpanelClient) {
        #if DEBUG
        client.flush(performFullFlush: true)
        #endif
    }
}

private extension Dictionary where Key == String, Value == TelemetryValue {
    var mixpanelProperties: Properties {
        reduce(into: Properties()) { partialResult, entry in
            partialResult[entry.key] = entry.value.mixpanelValue
        }
    }
}

private extension TelemetryValue {
    var mixpanelValue: MixpanelType {
        switch self {
        case .string(let value):
            value
        case .int(let value):
            value
        case .double(let value):
            value
        case .bool(let value):
            value
        }
    }
}
