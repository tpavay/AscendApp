import SwiftUI

/// The heart-rate sticker: the climb's trace as a line, then average and max.
struct StickerHeartRateContent: View {
    private static let traceSize = CGSize(width: 118, height: 34)

    private let subject: ShareSheetSubject
    private let points: [CGPoint]
    let ink: StickerInk

    init?(subject: ShareSheetSubject, ink: StickerInk) {
        guard subject.hasHeartRate, subject.heartRateTrace.count >= 2 else { return nil }
        self.subject = subject
        self.ink = ink
        points = Self.points(for: subject.heartRateTrace, in: Self.traceSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            StickerPolylineShape(points: points)
                .stroke(ink.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: Self.traceSize.width, height: Self.traceSize.height)
            ink.text(valueLine, size: 12)
            ink.caption("HEART RATE \u{00B7} BPM")
        }
    }

    private var valueLine: String {
        guard let average = subject.averageHeartRate else { return "" }
        guard let maximum = subject.maxHeartRate else { return "\(average) AVG" }
        return "\(average) AVG \u{00B7} \(maximum) MAX"
    }

    /// The series scaled to the box, a point of padding top and bottom so the stroke is not cut.
    private static func points(for trace: [Double], in size: CGSize) -> [CGPoint] {
        let lowest = trace.min() ?? 0
        let span = max((trace.max() ?? 0) - lowest, 1)
        let inset: CGFloat = 1
        let usable = size.height - inset * 2
        let lastIndex = CGFloat(trace.count - 1)
        return trace.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) / lastIndex * size.width,
                y: size.height - inset - CGFloat((value - lowest) / span) * usable
            )
        }
    }
}
