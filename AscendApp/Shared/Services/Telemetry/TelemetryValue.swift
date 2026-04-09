import Foundation

enum TelemetryValue: Sendable, Hashable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    var firebaseValue: Any {
        switch self {
        case .string(let value):
            value
        case .int(let value):
            value
        case .double(let value):
            value
        case .bool(let value):
            value
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value):
            value
        case .int(let value):
            String(value)
        case .double(let value):
            String(value)
        case .bool(let value):
            value ? "true" : "false"
        }
    }
}
