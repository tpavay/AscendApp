import Foundation

/// A colour as hex plus alpha, so palette decisions stay SwiftUI-free and testable.
struct ShareColor: Equatable, Sendable {
    let hex: UInt32
    let alpha: Double

    init(_ hex: UInt32, alpha: Double = 1) {
        self.hex = hex
        self.alpha = alpha
    }

    static let ink = ShareColor(0x0B0B0B)
    static let paper = ShareColor(0xFFFFFF)
}
