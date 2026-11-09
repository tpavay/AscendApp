import SwiftUI

/// The height sheet's vertical ruler, tallest mark at the top, under a fixed pointer at its middle.
/// The marks follow the finger, the way the weight scale's ticks do: the next taller mark is above
/// the pointer, so dragging the strip down brings it under and reads taller, and dragging up reads
/// shorter. It carries momentum on release and snaps to the nearest inch (a centimetre in metric).
///
/// The rows are laid out tallest first, so the row the scroll view centres is the mark drawn under
/// the pointer - one list, one order. Laying the rows out shortest first and mirroring the marks
/// over them put the finger and the value in opposite directions.
///
/// `value` is in the ruler's own unit: inches for imperial, centimetres for metric. The ruler is
/// rebuilt when the unit changes, so it opens at the converted value.
struct HeightRulerView: View {
    static let rowHeight: CGFloat = 15
    static let viewHeight: CGFloat = 270
    static let stripWidth: CGFloat = 160

    let system: MeasurementSystem
    @Binding var value: Int

    @State private var position: Int?

    /// The marks in the order the strip lays them out, top to bottom: the tallest first, so the row
    /// above any mark is the next taller one and dragging the strip down raises the value.
    nonisolated static func rows(in range: ClosedRange<Int>) -> [Int] {
        Array(range.reversed())
    }

    private var range: ClosedRange<Int> {
        switch system {
        case .imperial: ProfileMeasures.heightInchesRange
        case .metric: ProfileMeasures.heightCentimetersRange
        }
    }

    /// Feet in inches, or tens of centimetres: where the stronger tap and the long tick fall.
    private var major: Int { system == .imperial ? 12 : 10 }
    private var half: Int { system == .imperial ? 6 : 5 }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Self.rows(in: range), id: \.self) { mark in
                    tick(for: mark)
                        .frame(height: Self.rowHeight)
                        .id(mark)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .center)
        .contentMargins(.vertical, (Self.viewHeight - Self.rowHeight) / 2, for: .scrollContent)
        .frame(width: Self.stripWidth, height: Self.viewHeight)
        .overlay(alignment: .trailing) {
            // One continuous edge for the ticks to hang from, drawn once rather than per row.
            Rectangle()
                .fill(Color(hex: "444444"))
                .frame(width: 2)
                .allowsHitTesting(false)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.16),
                    .init(color: .black, location: 0.84),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear { position = value }
        .onChange(of: position) { _, new in
            if let new, new != value { value = new }
        }
        .sensoryFeedback(trigger: position) { old, new in
            guard old != nil, let new else { return nil }
            return new % major == 0 ? .impact(weight: .medium) : .selection
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Height")
        .accessibilityValue(spokenValue)
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1 : -1
            let next = min(max(value + step, range.lowerBound), range.upperBound)
            position = next
            value = next
        }
    }

    private var spokenValue: String {
        switch system {
        case .imperial: "\(value / 12) feet \(value % 12) inches"
        case .metric: "\(value) centimetres"
        }
    }

    /// One row: a tick hanging off the ruler's right edge, with a label on the longer two.
    private func tick(for mark: Int) -> some View {
        let isMajor = mark % major == 0
        let isHalf = mark % half == 0
        let length: CGFloat = isMajor ? 46 : isHalf ? 30 : 16

        return HStack(spacing: 8) {
            Spacer(minLength: 0)

            if let label = label(for: mark, isMajor: isMajor, isHalf: isHalf) {
                Text(label)
                    .font(.custom("Montserrat-ExtraBold", fixedSize: isMajor ? 13 : 11))
                    .foregroundStyle(isMajor ? Color(hex: "BDBDBD") : Color(hex: "6A6A6A"))
                    .lineLimit(1)
                    .fixedSize()
            }

            Rectangle()
                .fill(isMajor ? Color(hex: "BDBDBD") : isHalf ? Color(hex: "7A7A7A") : Color(hex: "4E4E4E"))
                .frame(width: length, height: isMajor ? 3 : 2)
        }
    }

    private func label(for mark: Int, isMajor: Bool, isHalf: Bool) -> String? {
        switch system {
        case .imperial:
            if isMajor { return "\(mark / 12) ft" }
            if isHalf { return "\(mark / 12)\u{2032}6\u{2033}" }
            return nil
        case .metric:
            return isMajor || isHalf ? "\(mark)" : nil
        }
    }
}
