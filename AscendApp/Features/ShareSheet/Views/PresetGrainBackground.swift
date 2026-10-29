import SwiftUI

/// A dark diagonal gradient warmed by the accent, under monochrome film grain.
struct PresetGrainBackground: View {
    let accentHex: UInt32

    private struct Bucket {
        let rects: [CGRect]
        let isLight: Bool
        let opacity: Double
    }

    private static let speckSize: CGFloat = 1
    private static let speckCount = 7_000

    /// Generated once from a fixed seed and capped, so the grain is identical on every draw and
    /// never costs more than a handful of fills.
    private static let buckets: [Bucket] = {
        var generator = PresetSeededGenerator(seed: 0xA5CE_4D01)
        let side = Double(PresetCardView.designSize)
        var light: [[CGRect]] = [[], [], []]
        var dark: [CGRect] = []
        for _ in 0..<speckCount {
            let rect = CGRect(
                x: Double.random(in: 0..<side, using: &generator),
                y: Double.random(in: 0..<side, using: &generator),
                width: speckSize,
                height: speckSize
            )
            let tier = Int.random(in: 0..<5, using: &generator)
            if tier < 3 { light[tier].append(rect) } else { dark.append(rect) }
        }
        return [
            Bucket(rects: light[0], isLight: true, opacity: 0.05),
            Bucket(rects: light[1], isLight: true, opacity: 0.09),
            Bucket(rects: light[2], isLight: true, opacity: 0.14),
            Bucket(rects: dark, isLight: false, opacity: 0.12)
        ]
    }()

    var body: some View {
        let side = PresetCardView.designSize
        let endpoints = PresetGradientGeometry.cssLinearEndpoints(angleDegrees: 155)
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(shareHex: 0x1A1A1A), location: 0),
                    .init(color: Color(share: .ink), location: 0.42),
                    .init(color: Color(shareHex: accentHex, opacity: 0x55 / 255, over: 0x0B0B0B), location: 1)
                ],
                startPoint: endpoints.start,
                endPoint: endpoints.end
            )
            Canvas { context, _ in
                for bucket in Self.buckets {
                    var path = Path()
                    path.addRects(bucket.rects)
                    let color: Color = bucket.isLight ? .white : .black
                    context.fill(path, with: .color(color.opacity(bucket.opacity)))
                }
            }
        }
        .frame(width: side, height: side)
    }
}
