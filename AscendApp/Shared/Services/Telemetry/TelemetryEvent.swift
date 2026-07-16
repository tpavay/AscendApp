import Foundation

protocol TelemetryEvent: Sendable {
    var record: TelemetryRecord { get }
}
