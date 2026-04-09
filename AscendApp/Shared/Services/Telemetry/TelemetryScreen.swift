import Foundation

struct TelemetryScreen: Sendable, Hashable, Equatable {
    let name: String
    let screenClass: String
    let parameters: [String: TelemetryValue]

    init(
        name: String,
        screenClass: String,
        parameters: [String: TelemetryValue] = [:]
    ) {
        self.name = name
        self.screenClass = screenClass
        self.parameters = parameters
    }
}
