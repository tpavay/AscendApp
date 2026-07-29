import Foundation
@preconcurrency import Mixpanel

final class MixpanelTelemetrySink: TelemetrySink, @unchecked Sendable {
    let supportedDestinations: Set<TelemetryDestination> = [.analytics]

    private let configuration: AnalyticsConfiguration
    private let buildMetadata: TelemetryBuildMetadata
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
        self.makeClient = makeClient
    }

    func setCollectionEnabled(_ enabled: Bool) {
        withConfiguredClient { client, isNewClient in
            if enabled && !isNewClient {
                client.registerSuperProperties(buildMetadata.properties)
            }
            client.setCollectionEnabled(enabled)
        }
    }

    func setUserID(_ userID: String?) {
        withConfiguredClient { client, _ in
            client.setUserID(userID)
            if userID == nil {
                client.registerSuperProperties(buildMetadata.properties)
            }
        }
    }

    func setUserProperty(_ name: String, value: String?) {
        withConfiguredClient { client, _ in
            client.setUserProperty(name, value: value)
            if buildMetadata.properties[name] != nil {
                client.registerSuperProperties(buildMetadata.properties)
            }
            flushAfterDebugEvent(client)
        }
    }

    func record(_ record: TelemetryRecord) {
        withConfiguredClient { client, _ in
            client.track(
                event: record.name,
                properties: record.parameters.mixpanelProperties
            )
            flushAfterDebugEvent(client)
        }
    }

    func record(screen: TelemetryScreen) {
        withConfiguredClient { client, _ in
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

    private func withConfiguredClient(
        _ action: (any MixpanelClient, _ isNewClient: Bool) -> Void
    ) {
        guard let token = configuration.mixpanelToken else { return }

        lock.lock()
        defer { lock.unlock() }

        if let client {
            action(client, false)
            return
        }

        let client = makeClient(token, flushInterval)
        #if DEBUG
        client.loggingEnabled = true
        #endif
        client.registerSuperProperties(buildMetadata.properties)
        self.client = client
        action(client, true)
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
