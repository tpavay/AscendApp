import SwiftUI

/// Renders a resolved stat in a given visual style, font, color, and optional
/// backing plate. Pure SwiftUI (no UIViewRepresentable) so `ImageRenderer` can
/// rasterize it at export time.
///
/// One styled view that any stat can use — adding a stat never touches this
/// file, and adding a style/font is one new branch reused by every stat.
struct ShareStatStickerContent: View {
    let stat: ResolvedShareStat
    var style: ShareStickerStyle = .display
    var font: ShareStickerFont = .montserrat
    var color: RGBAColor = .white
    var textBackground: ShareTextBackground = .none
    /// Base scale for the value text. The canvas/exporter further scales via
    /// `.scaleEffect`; this is the intrinsic size.
    var baseValueSize: CGFloat = 40

    private let lime = Color(red: 0.706, green: 0.8, blue: 0)

    private var valueColor: Color { color.color }
    /// Default (white) keeps the signature lime label; a custom color goes
    /// monochrome (label adopts the chosen color).
    private var labelColor: Color { color.isWhite ? lime : color.color }
    private var showsLabel: Bool { stat.kind != .climbName && !stat.label.isEmpty }

    var body: some View {
        styledContent
            .shadow(color: .black.opacity(textBackground == .none ? 0.45 : 0), radius: 6, x: 0, y: 2)
            .padding(plateInsets)
            .background(plate)
            .fixedSize()
    }

    @ViewBuilder
    private var styledContent: some View {
        switch style {
        case .display:
            VStack(spacing: 2) {
                Text(stat.value)
                    .font(font.swiftUIFont(size: baseValueSize))
                    .foregroundStyle(valueColor)
                if showsLabel {
                    Text(stat.label)
                        .font(font.swiftUIFont(size: baseValueSize * 0.3))
                        .tracking(2)
                        .foregroundStyle(labelColor)
                }
            }
        case .stacked:
            VStack(spacing: 1) {
                if showsLabel {
                    Text(stat.label)
                        .font(font.swiftUIFont(size: baseValueSize * 0.32))
                        .tracking(1.5)
                        .foregroundStyle(labelColor.opacity(0.9))
                }
                Text(stat.value)
                    .font(font.swiftUIFont(size: baseValueSize * 0.9))
                    .foregroundStyle(valueColor)
            }
        case .chip:
            HStack(spacing: 8) {
                if showsLabel {
                    Text(stat.label)
                        .font(font.swiftUIFont(size: baseValueSize * 0.34))
                        .tracking(1)
                        .foregroundStyle(labelColor)
                }
                Text(stat.value)
                    .font(font.swiftUIFont(size: baseValueSize * 0.38))
                    .foregroundStyle(valueColor)
            }
        }
    }

    private var plateInsets: EdgeInsets {
        switch textBackground {
        case .none:
            return EdgeInsets()
        default:
            return EdgeInsets(top: baseValueSize * 0.28, leading: baseValueSize * 0.4,
                              bottom: baseValueSize * 0.28, trailing: baseValueSize * 0.4)
        }
    }

    @ViewBuilder
    private var plate: some View {
        switch textBackground {
        case .none:
            EmptyView()
        case .dark:
            RoundedRectangle(cornerRadius: baseValueSize * 0.3, style: .continuous)
                .fill(.black.opacity(0.6))
        case .grey:
            RoundedRectangle(cornerRadius: baseValueSize * 0.3, style: .continuous)
                .fill(.white.opacity(0.18))
        }
    }
}

/// Renders several resolved stats as one composite block in a chosen layout
/// (row / 2×2 grid / vertical column). Each cell is a small label-over-value
/// pair so multiple metrics read cleanly together.
struct ShareCompositeStatContent: View {
    let stats: [ResolvedShareStat]
    var layout: ShareStatLayout = .row
    var font: ShareStickerFont = .montserrat
    var color: RGBAColor = .white
    var textBackground: ShareTextBackground = .none
    /// Intrinsic size; the canvas/exporter scales the whole sticker via `.scaleEffect`.
    var baseValueSize: CGFloat = 30

    private let lime = Color(red: 0.706, green: 0.8, blue: 0)
    private var valueColor: Color { color.color }
    private var labelColor: Color { color.isWhite ? lime : color.color }

    var body: some View {
        arrangement
            .shadow(color: .black.opacity(textBackground == .none ? 0.45 : 0), radius: 6, x: 0, y: 2)
            .padding(plateInsets)
            .background(plate)
            .fixedSize()
    }

    @ViewBuilder
    private var arrangement: some View {
        switch layout {
        case .row:
            HStack(alignment: .center, spacing: baseValueSize * 0.6) {
                ForEach(Array(stats.enumerated()), id: \.offset) { cell($0.element) }
            }
        case .column:
            VStack(spacing: baseValueSize * 0.34) {
                ForEach(Array(stats.enumerated()), id: \.offset) { cell($0.element) }
            }
        case .grid:
            let rows = stride(from: 0, to: stats.count, by: 2).map { start in
                Array(stats[start..<min(start + 2, stats.count)])
            }
            VStack(spacing: baseValueSize * 0.38) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .center, spacing: baseValueSize * 0.6) {
                        ForEach(Array(pair.enumerated()), id: \.offset) { cell($0.element) }
                    }
                }
            }
        }
    }

    private func cell(_ stat: ResolvedShareStat) -> some View {
        VStack(spacing: 1) {
            Text(stat.label)
                .font(font.swiftUIFont(size: baseValueSize * 0.34))
                .tracking(1.3)
                .foregroundStyle(labelColor.opacity(0.9))
            Text(stat.value)
                .font(font.swiftUIFont(size: baseValueSize * 0.92))
                .foregroundStyle(valueColor)
        }
    }

    private var plateInsets: EdgeInsets {
        switch textBackground {
        case .none:
            return EdgeInsets()
        default:
            return EdgeInsets(top: baseValueSize * 0.45, leading: baseValueSize * 0.55,
                              bottom: baseValueSize * 0.45, trailing: baseValueSize * 0.55)
        }
    }

    @ViewBuilder
    private var plate: some View {
        switch textBackground {
        case .none:
            EmptyView()
        case .dark:
            RoundedRectangle(cornerRadius: baseValueSize * 0.3, style: .continuous)
                .fill(.black.opacity(0.6))
        case .grey:
            RoundedRectangle(cornerRadius: baseValueSize * 0.3, style: .continuous)
                .fill(.white.opacity(0.18))
        }
    }
}

#Preview {
    ZStack {
        Color.gray
        VStack(spacing: 30) {
            ShareStatStickerContent(stat: .init(kind: .steps, label: "STEPS", value: "2,096"), style: .display, font: .anton)
            ShareStatStickerContent(stat: .init(kind: .duration, label: "DURATION", value: "22:10"), style: .display, font: .playfair, color: .white, textBackground: .dark)
            ShareStatStickerContent(stat: .init(kind: .calories, label: "CAL", value: "317"), style: .chip, font: .spaceMono, color: RGBAColor(r: 0.95, g: 0.26, b: 0.21, a: 1))
            ShareCompositeStatContent(
                stats: [
                    .init(kind: .duration, label: "TIME", value: "20m 17s"),
                    .init(kind: .avgHeartRate, label: "AVG BPM", value: "131"),
                    .init(kind: .calories, label: "CAL", value: "255")
                ],
                layout: .row, font: .playfair
            )
        }
    }
    .preferredColorScheme(.dark)
}
