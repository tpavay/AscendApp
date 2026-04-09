import Foundation

protocol TelemetrySink: Sendable {
    var supportedDestinations: Set<TelemetryDestination> { get }
    func setCollectionEnabled(_ enabled: Bool)
    func setUserID(_ userID: String?)
    func record(_ record: TelemetryRecord)
    func record(screen: TelemetryScreen)
}
