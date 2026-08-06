import Foundation

struct EnvelopedTelemetryScreen: Sendable, Hashable, Equatable {
    let name: String
    let screenClass: String
    let parameters: [String: TelemetryValue]
    let envelope: TelemetryEnvelope

    init(screen: TelemetryScreen, envelope: TelemetryEnvelope) {
        name = screen.name
        screenClass = screen.screenClass
        self.envelope = envelope

        var parameters = screen.parameters
        parameters.merge(envelope.properties) { _, requiredValue in requiredValue }
        self.parameters = parameters
    }
}
