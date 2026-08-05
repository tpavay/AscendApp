import Foundation

struct TelemetryRecord: Sendable, Hashable, Equatable {
    let name: String
    let parameters: [String: TelemetryValue]
    let destinations: Set<TelemetryDestination>

    init(
        name: String,
        parameters: [String: TelemetryValue] = [:],
        destinations: Set<TelemetryDestination> = [.analytics]
    ) {
        self.name = name
        self.parameters = parameters
        self.destinations = destinations
    }
}
