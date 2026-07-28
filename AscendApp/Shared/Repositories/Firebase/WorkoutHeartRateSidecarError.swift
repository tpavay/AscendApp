import Foundation

enum WorkoutHeartRateSidecarError: String, Error, Equatable, Sendable {
    case missing
    case forbidden
    case oversized
    case invalidReference = "invalid_reference"
    case unsupportedEncoding = "unsupported_encoding"
    case integrityMismatch = "integrity_failed"
    case malformed
    case transient

    var diagnosticCode: String {
        rawValue
    }

    var isTransient: Bool {
        self == .transient
    }

    /// A sidecar the server reported as absent must stop being pointed at from the workout
    /// envelope - a dangling reference makes every other clean device fail its restore forever.
    /// Every other failure can still be temporary or local to one device, so the durable
    /// reference survives it.
    var preservesRemoteReference: Bool {
        self != .missing
    }
}
