import SwiftUI

/// A repeating staircase line pattern in the accent, fading to black toward the bottom left.
struct PresetStairsBackground: View {
    let accent: Color

    private static let tile: CGFloat = 24

    var body: some View {
        let side = PresetCardView.designSize
        ZStack {
            Canvas { context, _ in
                context.stroke(Self.stairsPath(), with: .color(accent.opacity(0.28)), lineWidth: 1)
            }
            LinearGradient(
                stops: [
                    .init(color: Color(share: .ink).opacity(0), location: 0),
                    .init(color: Color(share: .ink).opacity(0.95), location: 0.75)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
        .frame(width: side, height: side)
    }

    private static func stairsPath() -> Path {
        var step = Path()
        step.move(to: CGPoint(x: 0, y: 24))
        for index in 0..<4 {
            let offset = CGFloat(index) * 6
            step.addLine(to: CGPoint(x: offset, y: 18 - offset))
            step.addLine(to: CGPoint(x: offset + 6, y: 18 - offset))
        }

        var path = Path()
        let count = Int((PresetCardView.designSize / tile).rounded(.up))
        for row in 0..<count {
            for column in 0..<count {
                path.addPath(
                    step,
                    transform: CGAffineTransform(translationX: CGFloat(column) * tile, y: CGFloat(row) * tile)
                )
            }
        }
        return path
    }
}
