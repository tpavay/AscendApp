@preconcurrency import Mixpanel

protocol MixpanelClient: AnyObject {
    var loggingEnabled: Bool { get set }

    func setCollectionEnabled(_ enabled: Bool)
    func setUserID(_ userID: String?)
    func setUserProperty(_ name: String, value: String?)
    func registerSuperProperties(_ properties: [String: String])
    func track(event: String, properties: Properties)
    func flush(performFullFlush: Bool)
}
