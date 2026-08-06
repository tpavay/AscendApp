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

    /// Crashlytics keeps only the last 64 KB of log lines, and the envelope is
    /// already attached to every report as custom keys, so repeating it on each
    /// breadcrumb would buy nothing and cost history depth.
    var crashlyticsMessage: String {
        let serializedParameters = parameters
            .filter { TelemetryEnvelope.propertyKeys.contains($0.key) == false }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.stringValue)" }
            .joined(separator: " ")

        guard serializedParameters.isEmpty == false else {
            return name
        }

        return "\(name) \(serializedParameters)"
    }
}
