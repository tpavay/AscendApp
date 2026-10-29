import SwiftUI

extension Color {
    /// A palette colour from the share sheet's SwiftUI-free `ShareColor`.
    init(share color: ShareColor) {
        self.init(
            .sRGB,
            red: Double((color.hex >> 16) & 0xFF) / 255,
            green: Double((color.hex >> 8) & 0xFF) / 255,
            blue: Double(color.hex & 0xFF) / 255,
            opacity: color.alpha
        )
    }

    /// An opaque colour from a 24-bit hex value.
    init(shareHex hex: UInt32, opacity: Double = 1) {
        self.init(share: ShareColor(hex, alpha: opacity))
    }
}
