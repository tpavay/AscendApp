import SwiftUI

/// The weight sheet's horizontal tick scale. Drag it left or right under a fixed needle at its
/// middle; it keeps momentum on release and snaps to a pound, or half a kilogram in metric.
///
/// `value` counts the scale's own steps: pounds for imperial, half kilograms for metric. The scale
/// is rebuilt when the unit changes, so it opens at the converted value.
struct WeightScaleView: View {
    static let stepWidth: CGFloat = 10
    static let viewHeight: CGFloat = 92

    let system: MeasurementSystem
    @Binding var value: Int

    @State private var position: Int?

    private var range: ClosedRange<Int> {
        switch system {
        case .imperial: ProfileMeasures.weightPoundsRange
        case .metric: ProfileMeasures.weightHalfKilogramsRange
        }
    }

    /// A labelled tick every 10 lb or 10 kg, a mid tick every 5.
    private var tenth: Int { system == .imperial ? 10 : 20 }
    private var fifth: Int { system == .imperial ? 5 : 10 }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(range), id: \.self) { mark in
                        tick(for: mark)
                            .frame(width: Self.stepWidth, height: Self.viewHeight)
                            .id(mark)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
            .contentMargins(.horizontal, (proxy.size.width - Self.stepWidth) / 2, for: .scrollContent)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.14),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .frame(height: Self.viewHeight)
        .onAppear { position = value }
        .onChange(of: position) { _, new in
            if let new, new != value { value = new }
        }
        .sensoryFeedback(trigger: position) { old, new in
            guard old != nil, let new else { return nil }
            return new % tenth == 0 ? .impact(weight: .medium) : .selection
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight")
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
        case .imperial: "\(value) pounds"
        case .metric: "\(ProfileMeasures.kilogramText(ProfileMeasures.kilograms(halfKilograms: value))) kilograms"
        }
    }

    /// One step: a tick hanging from the baseline, with a label under the long ones.
    private func tick(for mark: Int) -> some View {
        let isTen = mark % tenth == 0
        let isFive = mark % fifth == 0
        let length: CGFloat = isTen ? 38 : isFive ? 26 : 15

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(Color(hex: "444444"))
                .frame(height: 2)
                .padding(.top, 10)

            Rectangle()
                .fill(isTen ? Color(hex: "BDBDBD") : isFive ? Color(hex: "7A7A7A") : Color(hex: "4E4E4E"))
                .frame(width: 2, height: length)
                .padding(.top, 10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if isTen {
                Text(system == .imperial ? "\(mark)" : "\(mark / 2)")
                    .font(.custom("Montserrat-ExtraBold", fixedSize: 13))
                    .foregroundStyle(Color(hex: "9A9A9A"))
                    .fixedSize()
                    .padding(.top, 56)
            }
        }
    }
}
