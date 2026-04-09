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

    var crashlyticsMessage: String {
        guard !parameters.isEmpty else {
            return name
        }

        let serializedParameters = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.stringValue)" }
            .joined(separator: " ")

        return "\(name) \(serializedParameters)"
    }
}
