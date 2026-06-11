import Foundation
@preconcurrency import Mixpanel

final class MixpanelTelemetrySink: TelemetrySink, @unchecked Sendable {
    let supportedDestinations: Set<TelemetryDestination> = [.analytics]

    private let configuration: AnalyticsConfiguration
    private let lock = NSLock()
    private var instance: MixpanelInstance?

    init(configuration: AnalyticsConfiguration = .live) {
        self.configuration = configuration
    }

    func setCollectionEnabled(_ enabled: Bool) {
        guard let instance = configuredInstance() else { return }

        if enabled {
            instance.optInTracking()
        } else {
            instance.optOutTracking()
        }
    }

    func setUserID(_ userID: String?) {
        guard let instance = configuredInstance() else { return }

        if let userID {
            instance.identify(distinctId: userID, usePeople: false)
        } else {
            instance.reset()
        }
    }

    func setUserProperty(_ name: String, value: String?) {
        guard let instance = configuredInstance() else { return }

        if let value {
            instance.registerSuperProperties([name: value])
        } else {
            instance.unregisterSuperProperty(name)
        }
    }

    func record(_ record: TelemetryRecord) {
        configuredInstance()?.track(
            event: record.name,
            properties: record.parameters.mixpanelProperties
        )
    }

    func record(screen: TelemetryScreen) {
        var properties = screen.parameters.mixpanelProperties
        properties["screen_name"] = screen.name
        properties["screen_class"] = screen.screenClass

        configuredInstance()?.track(
            event: "screen_view",
            properties: properties
        )
    }

    private func configuredInstance() -> MixpanelInstance? {
        guard let token = configuration.mixpanelToken else { return nil }

        lock.lock()
        defer { lock.unlock() }

        if let instance {
            return instance
        }

        let instance = Mixpanel.initialize(
            token: token,
            trackAutomaticEvents: false
        )
        self.instance = instance
        return instance
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
