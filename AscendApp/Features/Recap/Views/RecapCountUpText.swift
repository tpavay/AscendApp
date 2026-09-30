import SwiftUI

/// A number that counts up to its value once, over about a second, when its page appears.
/// Under Reduce Motion it simply shows the value.
///
/// The final value lays out invisibly underneath, so the count never shifts what is
/// around it as digits are added.
struct RecapCountUpText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Int
    let font: Font
    var alignment: Alignment = .leading
    var delay: TimeInterval = 0
    /// Starts at the final value - for evidence renders, which capture a still frame.
    var isStatic = false

    @State private var displayed: Double?

    var body: some View {
        Text(Self.format(Double(value)))
            .font(font)
            .monospacedDigit()
            .hidden()
            .overlay(alignment: alignment) {
                Color.clear
                    .modifier(CountingText(value: displayed ?? (isStatic ? Double(value) : 0), font: font))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value.formatted())
            .task(id: value) {
                guard !reduceMotion, !isStatic else {
                    displayed = Double(value)
                    return
                }
                displayed = 0
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(.easeOut(duration: 1.0)) {
                    displayed = Double(value)
                }
            }
    }

    static func format(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.grouping(.automatic))
    }
}

/// Re-renders the digits at every animation frame so they count rather than jump.
private struct CountingText: ViewModifier, @preconcurrency Animatable {
    var value: Double
    let font: Font

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text(RecapCountUpText.format(value))
            .font(font)
            .monospacedDigit()
            .fixedSize()
    }
}
