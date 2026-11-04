import SwiftUI

/// The colours of the v3 onboarding design, from the handoff. Accent is the app's own lime, not
/// the design's lighter green, and the medals are the app's tokens.
enum OnboardingV3Palette {
    static let background = Color.black
    static let progressTrack = Color(hex: "262626")
    static let progressFillStart = Color(hex: "6FB000")
    static let progressFillEnd = Color(hex: "A8E24A")
    static let body = Color(hex: "D2D2D2")
    static let secondary = Color(hex: "A8A8A8")
    static let skip = Color(hex: "9A9A9A")
    static let controlFill = Color(hex: "141414")
    static let cardFill = Color(hex: "0C0C0C")
    static let cardBorder = Color(hex: "1E1E1E")
    static let chipBorder = Color(hex: "262626")
    static let orange = Color(hex: "F0A050")
    static let accent = Color.ascendAccent
    static let gold = Color.ascendMedalGold
}

// MARK: - Headline

/// The uppercase Black headline. The last line or lines are in the accent: lime by default, medal
/// gold on 03 and 09, orange on 04.
struct OnboardingHeadline: View {
    enum Accent {
        case lime, gold, orange

        var color: Color {
            switch self {
            case .lime: OnboardingV3Palette.accent
            case .gold: OnboardingV3Palette.gold
            case .orange: OnboardingV3Palette.orange
            }
        }
    }

    private let leadLines: [String]
    private let accentLines: [String]
    private let accent: Accent
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 34

    /// - Parameters:
    ///   - lead: The lines in white.
    ///   - accentLines: The closing line or lines in the accent.
    ///   - size: 46 on the welcome screen, 34 typically, 31 to 38 elsewhere.
    init(_ lead: [String], accentLines: [String] = [], accent: Accent = .lime, size: CGFloat = 34) {
        leadLines = lead
        self.accentLines = accentLines
        self.accent = accent
        _size = ScaledMetric(wrappedValue: size, relativeTo: .title)
    }

    var body: some View {
        text
            .textCase(.uppercase)
            .lineHeight(.exact(points: size * 0.96))
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((leadLines + accentLines).joined(separator: " "))
            .accessibilityAddTraits(.isHeader)
    }

    private var text: Text {
        let lead = leadLines.joined(separator: "\n")
        let closing = accentLines.joined(separator: "\n")

        guard !closing.isEmpty else { return styled(lead, color: .white) }
        guard !lead.isEmpty else { return styled(closing, color: accent.color) }

        return Text("\(styled(lead + "\n", color: .white))\(styled(closing, color: accent.color))")
    }

    private func styled(_ string: String, color: Color) -> Text {
        Text(string)
            .font(.custom("Montserrat-Black", fixedSize: size))
            .tracking(-size * 0.02)
            .foregroundStyle(color)
    }
}

// MARK: - Text

private struct OnboardingBodyTextStyle: ViewModifier {
    enum Tone { case primary, secondary }

    let tone: Tone
    @ScaledMetric(relativeTo: .body) private var primarySize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var secondarySize: CGFloat = 15

    func body(content: Content) -> some View {
        switch tone {
        case .primary:
            content
                .font(.custom("Montserrat-SemiBold", fixedSize: primarySize))
                .foregroundStyle(OnboardingV3Palette.body)
                .lineSpacing(primarySize * 0.22)
        case .secondary:
            content
                .font(.custom("Montserrat-Medium", fixedSize: secondarySize))
                .foregroundStyle(OnboardingV3Palette.secondary)
                .lineSpacing(secondarySize * 0.28)
        }
    }
}

private struct OnboardingKickerStyle: ViewModifier {
    let color: Color
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 11.5

    func body(content: Content) -> some View {
        content
            .font(.custom("Montserrat-ExtraBold", fixedSize: size))
            .tracking(size * 0.18)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

extension View {
    /// SemiBold 17, line height 1.45, `#D2D2D2`.
    func onboardingBody() -> some View {
        modifier(OnboardingBodyTextStyle(tone: .primary))
    }

    /// 15 pt `#A8A8A8`, for the line under a headline that carries less weight than the body.
    func onboardingSecondary() -> some View {
        modifier(OnboardingBodyTextStyle(tone: .secondary))
    }

    /// ExtraBold 11 to 12 pt, tracked 0.18 em, uppercase.
    func onboardingKicker(color: Color = OnboardingV3Palette.accent) -> some View {
        modifier(OnboardingKickerStyle(color: color))
    }
}

// MARK: - Buttons

/// The primary action: 60 pt, 16 pt radius, accent fill, black ExtraBold uppercase. Dimmed when
/// disabled, which is how 07b keeps CONTINUE quiet until a row is tapped.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Montserrat-ExtraBold", fixedSize: fontSize))
            .tracking(fontSize * 0.14)
            .textCase(.uppercase)
            .foregroundStyle(Color.black)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(OnboardingV3Palette.accent)
            )
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// The quiet link under a primary action: 44 pt tall, SemiBold 14, `#A8A8A8`.
struct OnboardingQuietLinkStyle: ButtonStyle {
    @ScaledMetric(relativeTo: .subheadline) private var fontSize: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Montserrat-SemiBold", fixedSize: fontSize))
            .foregroundStyle(OnboardingV3Palette.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == OnboardingPrimaryButtonStyle {
    static var onboardingPrimary: OnboardingPrimaryButtonStyle { OnboardingPrimaryButtonStyle() }
}

extension ButtonStyle where Self == OnboardingQuietLinkStyle {
    static var onboardingQuietLink: OnboardingQuietLinkStyle { OnboardingQuietLinkStyle() }
}

// MARK: - Card

private struct OnboardingCardStyle: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(OnboardingV3Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(OnboardingV3Palette.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    /// `#0C0C0C` fill and a 1 pt `#1E1E1E` border. The design uses radii from 16 to 24.
    func onboardingCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(OnboardingCardStyle(cornerRadius: cornerRadius))
    }
}

// MARK: - Select row

/// A tappable choice. Tapping lights an accent border and a soft glow; there is no check mark and
/// no radio circle (the captain's call, round 45). The selected state is spoken, not drawn as a
/// glyph, so it reaches VoiceOver through the selected trait.
struct OnboardingSelectRow: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize: CGFloat = 13

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("Montserrat-ExtraBold", fixedSize: titleSize))
                        .foregroundStyle(Color.white)

                    if let subtitle {
                        Text(subtitle)
                            .font(.custom("Montserrat-Medium", fixedSize: subtitleSize))
                            .foregroundStyle(OnboardingV3Palette.secondary)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? OnboardingV3Palette.accent.opacity(0.1) : OnboardingV3Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? OnboardingV3Palette.accent : OnboardingV3Palette.cardBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? OnboardingV3Palette.accent.opacity(0.28) : .clear, radius: 14)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Onboarding styles") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("Kicker").onboardingKicker()
            OnboardingHeadline(["Stop staring"], accentLines: ["at the clock."], size: 46)
            OnboardingHeadline(["See yourself"], accentLines: ["get better."], accent: .gold)
            Text("Ascend turns every stair stepper session into a climb up a real mountain.")
                .onboardingBody()
            Text("Secondary line").onboardingSecondary()
            OnboardingSelectRow(title: "30 to 45 min", subtitle: "~3,000 steps", isSelected: true) {}
            OnboardingSelectRow(title: "Under 15 min", subtitle: "~1,000 steps", isSelected: false) {}
            VStack { Text("Card").foregroundStyle(.white).padding() }
                .frame(maxWidth: .infinity)
                .onboardingCard()
            Button("Continue") {}.buttonStyle(.onboardingPrimary)
            Button("Not now") {}.buttonStyle(.onboardingQuietLink)
        }
        .padding(24)
    }
    .background(Color.black)
}
