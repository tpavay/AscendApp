import SwiftUI

/// SwiftUI-layer resolvers for the background layer's SwiftUI-free enums. Kept
/// out of the model/view-model layer so those stay free of `Color`.
/// The card format's own resolvers live in `ShareCardStyleResolvers`.

extension View {
    /// Applies a background filter's color grade. Resolution-independent
    /// adjustments only, so the editing canvas and the export render identically.
    @ViewBuilder
    func shareBackgroundFilter(_ filter: ShareBackgroundFilter) -> some View {
        switch filter {
        case .original:
            self
        case .mono:
            grayscale(1).contrast(1.05)
        case .noir:
            grayscale(1).contrast(1.4).brightness(-0.06)
        case .vivid:
            saturation(1.55).contrast(1.08)
        case .fade:
            saturation(0.72).contrast(0.88).brightness(0.07)
        case .warm:
            colorMultiply(Color(red: 1.0, green: 0.9, blue: 0.78)).saturation(1.1)
        case .cool:
            colorMultiply(Color(red: 0.82, green: 0.9, blue: 1.0)).saturation(1.05)
        case .zoomBlur, .motionBlur, .fisheye:
            // Geometric filters are baked into a processed image via Core Image;
            // no color adjustment here.
            self
        }
    }
}

extension RGBAColor {
    var color: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }

    var isWhite: Bool {
        r > 0.97 && g > 0.97 && b > 0.97 && a > 0.97
    }
}
