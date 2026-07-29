@preconcurrency import Mixpanel

final class MixpanelSDKClient: MixpanelClient {
    var loggingEnabled: Bool {
        get { instance.loggingEnabled }
        set { instance.loggingEnabled = newValue }
    }

    private let instance: MixpanelInstance

    init(token: String, flushInterval: Double) {
        instance = Mixpanel.initialize(
            token: token,
            trackAutomaticEvents: false,
            flushInterval: flushInterval
        )
    }

    func setCollectionEnabled(_ enabled: Bool) {
        if enabled {
            instance.optInTracking()
        } else {
            instance.optOutTracking()
        }
    }

    func setUserID(_ userID: String?) {
        if let userID {
            instance.identify(distinctId: userID, usePeople: true)
        } else {
            instance.reset()
        }
    }

    func setUserProperty(_ name: String, value: String?) {
        if let value {
            instance.people.set(property: name, to: value)
            instance.registerSuperProperties([name: value])
        } else {
            instance.people.unset(properties: [name])
            instance.unregisterSuperProperty(name)
        }
    }

    func registerSuperProperties(_ properties: [String: String]) {
        instance.registerSuperProperties(properties)
    }

    func track(event: String, properties: Properties) {
        instance.track(event: event, properties: properties)
    }

    func flush(performFullFlush: Bool) {
        instance.flush(performFullFlush: performFullFlush)
    }
}
