import SwiftUI

/// SwiftUI resolvers for the card format's styling primitives. Kept out of the
/// model layer so the format stays `Font`/`Color`-free and unit-testable.

extension ShareStickerFont {
    /// The typeface at a given point size and weight role.
    ///
    /// `fixedSize` deliberately: the composer is a WYSIWYG image editor, so the
    /// canvas must match the exported pixels rather than track Dynamic Type.
    /// Faces that ship one weight render every role from that file.
    ///
    /// **The Dynamic Type boundary runs here, and only here.** Card content —
    /// stickers, the splits table, template text — is fixed because the exported
    /// image is the product: it renders at the default text size for everyone, so
    /// a canvas that scaled would show the author something the export cannot
    /// reproduce, and letting the export scale would make one template produce a
    /// different image per reader. The composer's own chrome — the add sheet, the
    /// font and structure pickers, action pills, toasts, the background picker —
    /// goes through `Font.montserrat*`, which is `relativeTo:` and **must keep
    /// scaling**: that is reading UI, not card content. Do not unify the two.
    func swiftUIFont(size: CGFloat, role: ShareCardFontRole = .heavy) -> Font {
        switch self {
        case .montserrat:
            switch role {
            case .heavy: return .custom("Montserrat-Bold", fixedSize: size)
            case .medium: return .custom("Montserrat-SemiBold", fixedSize: size)
            case .regular: return .custom("Montserrat-Medium", fixedSize: size)
            }
        case .anton:
            return .custom("Anton-Regular", fixedSize: size)
        case .playfair:
            return .custom("PlayfairDisplay-Italic", fixedSize: size)
        case .spaceMono:
            return .custom("SpaceMono-Bold", fixedSize: size)
        case .rounded:
            return .system(size: size, weight: role == .heavy ? .bold : .semibold, design: .rounded)
        case .thin:
            return .system(size: size, weight: .ultraLight)
        }
    }
}

extension ShareCardColor {
    func color(in context: ShareCardRenderContext) -> Color {
        switch self {
        case .value: return context.valueColor.color
        case .label: return context.labelColor.color
        case .hex(let hex): return Self.color(fromHex: hex)
        }
    }

    static func color(fromHex hex: String) -> Color {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(cleaned, radix: 16) ?? 0
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension ShareCardTint {
    func color(in context: ShareCardRenderContext) -> Color {
        color.color(in: context).opacity(opacity)
    }
}

extension ShareCardUnitPoint {
    var unitPoint: UnitPoint {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        case .center: return .center
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

extension ShareCardAlignment {
    var alignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center, .firstTextBaseline: return .center
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    /// Cross-axis alignment for a vertical stack.
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading, .topLeading, .bottomLeading: return .leading
        case .trailing, .topTrailing, .bottomTrailing: return .trailing
        default: return .center
        }
    }

    /// Cross-axis alignment for a horizontal stack.
    var vertical: VerticalAlignment {
        switch self {
        case .top, .topLeading, .topTrailing: return .top
        case .bottom, .bottomLeading, .bottomTrailing: return .bottom
        case .firstTextBaseline: return .firstTextBaseline
        default: return .center
        }
    }
}

extension ShareCardTextAlignment {
    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

extension ShareCardEdgeInsets {
    var edgeInsets: EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }
}

extension ShareCardDimension {
    var length: CGFloat {
        switch self {
        case .points(let value): return value
        case .infinity: return .infinity
        }
    }
}

/// One of the format's shapes, erased so a modifier can fill, stroke, or clip
/// with whichever the template named.
struct ShareCardShapeView: Shape {
    let kind: ShareCardShapeKind

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .rectangle:
            return Rectangle().path(in: rect)
        case .roundedRectangle(let cornerRadius):
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        case .capsule:
            return Capsule(style: .continuous).path(in: rect)
        case .circle:
            return Circle().path(in: rect)
        }
    }
}

extension View {
    /// Paints a format fill behind the view in the given shape.
    @ViewBuilder
    func shareCardFill(
        _ fill: ShareCardFill?,
        shape: ShareCardShapeKind,
        context: ShareCardRenderContext
    ) -> some View {
        if let fill {
            background(ShareCardFillView(fill: fill, context: context).clipShape(ShareCardShapeView(kind: shape)))
        } else {
            self
        }
    }
}

/// Draws a format fill — solid, gradient, or material.
struct ShareCardFillView: View {
    let fill: ShareCardFill
    let context: ShareCardRenderContext

    var body: some View {
        switch fill {
        case .color(let tint):
            Rectangle().fill(tint.color(in: context))
        case .linearGradient(let stops, let start, let end):
            LinearGradient(
                colors: stops.map { $0.color(in: context) },
                startPoint: start.unitPoint,
                endPoint: end.unitPoint
            )
        case .radialGradient(let stops, let center, let startRadius, let endRadius):
            RadialGradient(
                colors: stops.map { $0.color(in: context) },
                center: center.unitPoint,
                startRadius: startRadius,
                endRadius: endRadius
            )
        case .material(let material, let opacity):
            materialView(material).opacity(opacity)
        }
    }

    @ViewBuilder
    private func materialView(_ material: ShareCardMaterial) -> some View {
        switch material {
        case .ultraThin: Rectangle().fill(.ultraThinMaterial)
        case .thin: Rectangle().fill(.thinMaterial)
        case .regular: Rectangle().fill(.regularMaterial)
        }
    }
}
