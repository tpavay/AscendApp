import SwiftUI

/// A small phone showing Apple's Health access sheet with the two taps ringed, so the climber knows
/// what is about to appear before iOS asks. Drawn natively and scaled to the room it is given.
///
/// It is a picture of Ascend's real request, redrawn from the simulator: the four types
/// `HealthKitAuthorizationClient.readTypes` asks for and nothing else, and "access", never
/// "update", because Ascend only reads (the system's own sentence on the real sheet still says "access
/// and update" while the Info.plist declares `NSHealthUpdateUsageDescription`). A type added to the request has to be added to
/// ``categories`` in the same change, or the picture tells the climber the wrong thing.
struct HealthPermissionSheetMock: View {
    /// The rows the real sheet lists under "Allow Ascend to read", in the order iOS sorts them.
    static let categories = ["Active Energy", "Heart Rate", "Steps", "Workouts"]

    /// What the picture is called to VoiceOver, which cannot see the drawing.
    static let accessibilityDescription = "Preview of the Apple Health permission screen: tap Turn On All, then Allow"

    /// How wide the phone's bezel is drawn. It sits above the sheet, so it hides anything under it.
    static let bezelWidth: CGFloat = 6

    /// How far a target's pulse spreads past its ring: exactly the room between a target inset 12
    /// points and the bezel, so the pulse fades out as it reaches the bezel instead of sliding under it.
    static let pulseSpread: CGFloat = 6

    private static let baseSize = CGSize(width: 230, height: 390)

    @OnboardingReduceMotion private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, proxy.size.width / Self.baseSize.width, proxy.size.height / Self.baseSize.height)

            phone
                .frame(width: Self.baseSize.width, height: Self.baseSize.height)
                .scaleEffect(scale)
                .frame(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityDescription)
        .accessibilityAddTraits(.isImage)
    }

    // MARK: - The phone

    private var phone: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color(hex: "0A0A0A"))

            sheet
                .padding(.top, 40)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .strokeBorder(Color(hex: "1E1E1E"), lineWidth: Self.bezelWidth)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .strokeBorder(Color(hex: "333333"), lineWidth: 1)
        )
        // Above the bezel, because the "1" straddles it.
        .overlay(alignment: .topLeading) {
            numberBadge("1")
                .offset(x: 1, y: 150)
            numberBadge("2")
                .offset(x: 230 - 12 - 22, y: 296)
        }
        .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
        .shadow(color: .black.opacity(0.8), radius: 30, y: 30)
    }

    // MARK: - Apple's sheet

    /// The categories' icons and colours as Health draws them, in the order iOS sorts them.
    private static let rowSymbols: [String: (symbol: String, color: Color)] = [
        "Active Energy": ("flame.fill", Color(hex: "FF6A00")),
        "Heart Rate": ("heart.fill", Color(hex: "FF2D55")),
        "Steps": ("figure.walk", Color(hex: "FF9500")),
        "Workouts": ("figure.run", Color(hex: "30D158"))
    ]

    /// iOS 26's sheet: a title, Health's icon, what is asked, Turn On All, one switch for each type,
    /// and Allow and Don't Allow at the bottom, which is where the climber has to look for Allow.
    private var sheet: some View {
        VStack(spacing: 0) {
            Text("Health Access")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 9)

            Image("appleHealth-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.top, 9)

            VStack(alignment: .leading, spacing: 1) {
                Text("Health")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                Text("\"Ascend\" would like to access your Health data.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color(hex: "8E8E93"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ringed {
                Text("Turn On All")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "0A84FF"))
                    .padding(.leading, 24)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .background(Capsule().fill(Color(hex: "2C2C2E")))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Text("Allow \"Ascend\" to read")
                .font(.system(size: 8))
                .foregroundStyle(Color(hex: "8E8E93"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 3)

            VStack(spacing: 0) {
                ForEach(Array(Self.categories.enumerated()), id: \.offset) { index, name in
                    let look = Self.rowSymbols[name]
                    HStack(spacing: 6) {
                        Image(systemName: look?.symbol ?? "circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(look?.color ?? .gray)
                            .frame(width: 12)
                        Text(name)
                            .font(.system(size: 9))
                            .foregroundStyle(.white)
                        Spacer()
                        MockToggle()
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .overlay(alignment: .top) {
                        if index > 0 { Color(hex: "3A3A3C").frame(height: 0.5).padding(.leading, 27) }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: "2C2C2E")))
            .padding(.horizontal, 8)

            Spacer(minLength: 6)

            ringed {
                Text("Allow")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(Capsule().fill(Color(hex: "3A3A3C")))
            }
            .padding(.horizontal, 12)

            Text("Don't Allow")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 24)
                .overlay(Capsule().strokeBorder(Color(hex: "3A3A3C"), lineWidth: 1))
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "1C1C1E"))
    }

    // MARK: - Pieces

    /// A target with an accent outline and a pulse spreading from it every 1.3 s.
    private func ringed<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .overlay(
                Capsule()
                    .strokeBorder(OnboardingV3Palette.accent, lineWidth: 1.5)
            )
            .background(PulseRing(isStill: reduceMotion))
    }

    private func numberBadge(_ number: String) -> some View {
        Text(number)
            .font(.custom("Montserrat-Black", fixedSize: 12))
            .foregroundStyle(.black)
            .frame(width: 22, height: 22)
            .background(Circle().fill(OnboardingV3Palette.accent))
            .shadow(color: .black.opacity(0.6), radius: 5, y: 4)
    }
}

/// The ring's spreading pulse: the outline grows outward and fades out, over 1.3 s, on repeat. Reduce Motion draws nothing.
private struct PulseRing: View {
    let isStill: Bool

    @State private var isSpreading = false

    var body: some View {
        Capsule()
            .strokeBorder(OnboardingV3Palette.accent.opacity(0.85), lineWidth: 2)
            .padding(isSpreading ? -HealthPermissionSheetMock.pulseSpread : 0)
            .opacity(isStill ? 0 : isSpreading ? 0 : 0.85)
            .onAppear {
                guard !isStill else { return }
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                    isSpreading = true
                }
            }
    }
}

/// One of the sheet's switches, flipping on a 3 s loop: off for the first 45 percent, on by 55, and
/// back to off at the top of the next turn. Reduce Motion shows it on.
private struct MockToggle: View {
    @OnboardingReduceMotion private var reduceMotion

    private static let loop: TimeInterval = 3

    var body: some View {
        if reduceMotion {
            toggle(progress: 1)
        } else {
            TimelineView(.animation) { context in
                toggle(progress: Self.progress(at: context.date))
            }
        }
    }

    /// 0 while off, 1 while on, eased across the ten percent between.
    static func progress(at date: Date) -> Double {
        let position = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop) / loop
        guard position > 0.45 else { return 0 }
        guard position < 0.55 else { return 1 }
        let t = (position - 0.45) / 0.1
        return t * t * (3 - 2 * t)
    }

    private func toggle(progress: Double) -> some View {
        Capsule()
            .fill(Color(hex: "3A3A3C").mix(with: Color(hex: "34C759"), by: progress))
            .frame(width: 26, height: 16)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .padding(2)
                    .offset(x: 9 * progress)
            }
    }
}

#Preview("06b sheet mock") {
    HealthPermissionSheetMock()
        .frame(height: 420)
        .background(Color.black)
}
