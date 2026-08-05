import Foundation

protocol TelemetrySink: Sendable {
    var supportedDestinations: Set<TelemetryDestination> { get }
    func setCollectionEnabled(_ enabled: Bool)
    func setUserID(_ userID: String?)
    func setUserProperty(_ name: String, value: String?)
    func record(_ record: EnvelopedTelemetryRecord)
    func record(screen: EnvelopedTelemetryScreen)
}

extension TelemetrySink {
    func setUserProperty(_ name: String, value: String?) {}
}
