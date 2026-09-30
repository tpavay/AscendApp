import SwiftUI

/// The recap's shared type and chrome, so every page reads as one story.
enum RecapStyle {
    static let sectionLabelFont = Font.montserratBold(size: 11)
    static let sectionLabelTracking: CGFloat = 2.2
    static let secondaryText = Color.white.opacity(0.7)
    static let tertiaryText = Color.white.opacity(0.55)
    static let tileFill = Color(hex: "111113")
    static let tileStroke = Color.white.opacity(0.08)
}

/// A letter-spaced section label: `YOUR WEEK`, `EARNED THIS WEEK`.
struct RecapSectionLabel: View {
    let text: String
    var color: Color = RecapStyle.tertiaryText

    init(_ text: String, color: Color = RecapStyle.tertiaryText) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(RecapStyle.sectionLabelFont)
            .tracking(RecapStyle.sectionLabelTracking)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The recap's one primary action, and its quiet secondary beneath.
struct RecapCallToAction: View {
    let title: String
    var secondaryTitle: String?
    let action: () -> Void
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Button(action: action) {
                Text(title)
                    .font(.montserratBold(size: 15))
                    .tracking(1)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(Color.accent))
            }
            .buttonStyle(.plain)

            if let secondaryTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.montserratBold(size: 12))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.86))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Content rising into place when its page appears, staggered by `order`. Under Reduce
/// Motion it only fades.
struct RecapEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.recapIsStatic) private var isStatic

    let order: Int
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .opacity(isShown || isStatic ? 1 : 0)
            .offset(y: isShown || isStatic || reduceMotion ? 0 : 14)
            .onAppear {
                guard !isStatic else { return }
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.2)
                        : .spring(response: 0.45, dampingFraction: 0.86).delay(Double(order) * 0.06)
                ) {
                    isShown = true
                }
            }
    }
}

extension View {
    func recapEntrance(_ order: Int) -> some View {
        modifier(RecapEntrance(order: order))
    }
}

extension EnvironmentValues {
    /// Holds every recap animation at its end state - for evidence renders, which
    /// photograph a single frame.
    @Entry var recapIsStatic = false
}
