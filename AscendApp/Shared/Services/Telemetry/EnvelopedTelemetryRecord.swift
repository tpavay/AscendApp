import Foundation

struct EnvelopedTelemetryRecord: Sendable, Hashable, Equatable {
    let name: String
    let parameters: [String: TelemetryValue]
    let destinations: Set<TelemetryDestination>
    let envelope: TelemetryEnvelope

    init(record: TelemetryRecord, envelope: TelemetryEnvelope) {
        name = record.name
        destinations = record.destinations
        self.envelope = envelope

        var parameters = record.parameters
        parameters.merge(envelope.properties) { _, requiredValue in requiredValue }
        self.parameters = parameters
    }

    var crashlyticsMessage: String {
        let serializedParameters = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.stringValue)" }
            .joined(separator: " ")

        return "\(name) \(serializedParameters)"
    }
}
