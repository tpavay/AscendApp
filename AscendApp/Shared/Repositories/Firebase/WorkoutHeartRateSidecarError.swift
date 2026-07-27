import Foundation

enum WorkoutHeartRateSidecarError: Error, Equatable, Sendable {
    case missing
    case forbidden
    case oversized
    case invalidReference
    case unsupportedEncoding
    case integrityMismatch
    case malformed
    case transient

    var diagnosticCode: String {
        switch self {
        case .missing: "missing"
        case .forbidden: "forbidden"
        case .oversized: "oversized"
        case .invalidReference: "invalid_reference"
        case .unsupportedEncoding: "unsupported_encoding"
        case .integrityMismatch: "integrity_failed"
        case .malformed: "malformed"
        case .transient: "transient"
        }
    }

    var isTransient: Bool {
        self == .transient
    }
}
