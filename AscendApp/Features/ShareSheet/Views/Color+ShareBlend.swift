import SwiftUI

extension Color {
    /// A colour at `opacity` already composited over an opaque backdrop. CSS interpolates a
    /// gradient in premultiplied space and SwiftUI does not, so a stop that is translucent next to
    /// an opaque neighbour would drift; precomposing over the backdrop makes both agree exactly.
    init(shareHex hex: UInt32, opacity: Double, over backdrop: UInt32) {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double {
            Double((value >> shift) & 0xFF) / 255
        }
        func blended(_ shift: UInt32) -> Double {
            channel(hex, shift) * opacity + channel(backdrop, shift) * (1 - opacity)
        }
        self.init(.sRGB, red: blended(16), green: blended(8), blue: blended(0), opacity: 1)
    }
}
