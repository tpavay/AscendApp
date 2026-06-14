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
            instance.identify(distinctId: userID, usePeople: true)
        } else {
            instance.reset()
        }
    }

    func setUserProperty(_ name: String, value: String?) {
        guard let instance = configuredInstance() else { return }

        if let value {
            instance.people.set(property: name, to: value)
            instance.registerSuperProperties([name: value])
        } else {
            instance.people.unset(properties: [name])
            instance.unregisterSuperProperty(name)
        }

        flushAfterDebugEvent(instance)
    }

    func record(_ record: TelemetryRecord) {
        guard let instance = configuredInstance() else { return }

        instance.track(
            event: record.name,
            properties: record.parameters.mixpanelProperties
        )

        flushAfterDebugEvent(instance)
    }

    func record(screen: TelemetryScreen) {
        guard let instance = configuredInstance() else { return }

        var properties = screen.parameters.mixpanelProperties
        properties["screen_name"] = screen.name
        properties["screen_class"] = screen.screenClass

        instance.track(
            event: "screen_view",
            properties: properties
        )

        flushAfterDebugEvent(instance)
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
            trackAutomaticEvents: false,
            flushInterval: flushInterval
        )
        #if DEBUG
        instance.loggingEnabled = true
        #endif
        self.instance = instance
        return instance
    }

    private var flushInterval: Double {
        #if DEBUG
        return 5
        #else
        return 60
        #endif
    }

    private func flushAfterDebugEvent(_ instance: MixpanelInstance) {
        #if DEBUG
        instance.flush(performFullFlush: true)
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
