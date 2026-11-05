import SwiftUI

/// 02 Go harder than you would alone: the Mountain in a tilted phone, with the three things that
/// make it harder to quit pinned beside it - a climber just ahead, your own best, and a pacer.
///
/// The chips are the Mountain's own views at fixed values (`AscendMountainCrowdChip`) and the
/// ghost labels its climbs carry. They pop in at 0.7, 0.95 and 1.2 s, each with a light tap.
struct OnboardingGoHarderScreen: View {
    let coordinator: OnboardingV3Coordinator

    @OnboardingReduceMotion private var reduceMotion

    private static let chipDelays: [Double] = [0.7, 0.95, 1.2]

    var body: some View {
        SellScreenFrame(
            step: .goHarder,
            headline: OnboardingHeadline(
                SellScreenCopy.GoHarder.headlineLead,
                accentLines: SellScreenCopy.GoHarder.headlineAccent
            ),
            message: SellScreenCopy.GoHarder.body,
            textDelay: 0.3,
            artMinimumHeight: 190,
            onContinue: coordinator.advance
        ) {
            art
        }
        .background(alignment: .top) {
            SellGlow(color: OnboardingV3Palette.accent)
                .frame(height: 480)
                .padding(.top, 70)
                .allowsHitTesting(false)
        }
        .task {
            for delay in Self.chipDelays {
                try? await Task.sleep(for: .seconds(delay - (Self.previous(before: delay) ?? 0)))
                guard !Task.isCancelled else { return }
                HapticsManager.shared.trigger(.lightImpact)
            }
        }
        .trackOnce(screen: .onboardingGoHarder)
    }

    private static func previous(before delay: Double) -> Double? {
        chipDelays.last { $0 < delay }
    }

    private var art: some View {
        GeometryReader { proxy in
            let phoneHeight = min(proxy.size.height - 12, proxy.size.width * 0.72 * 440 / 204)
            let phoneWidth = phoneHeight * 204 / 440
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                phone
                    .frame(width: phoneWidth, height: phoneHeight)
                    .rotationEffect(.degrees(-4))
                    .onboardingEntrance(style: .rise(SellMotion.phoneRise(reduceMotion: reduceMotion)), duration: 0.8)
                    .position(center)

                SellChipPlacement(center: CGPoint(x: center.x - phoneWidth * 0.34, y: center.y + phoneHeight * 0.28)) {
                    chip(SellGhostLabelChip(kind: .pacer(stepsPerMinute: 80)), index: 2)
                }

                SellChipPlacement(center: CGPoint(x: center.x + phoneWidth * 0.5, y: center.y + phoneHeight * 0.02)) {
                    chip(SellGhostLabelChip(kind: .personalBest), index: 1)
                }

                chip(
                    AscendMountainCrowdChip(count: 1, side: .ahead)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        // The real chip is a translucent black capsule made for the Mountain; on this
                        // black page it needs the hairline the other chips carry.
                        .background(Capsule(style: .continuous).fill(OnboardingV3Palette.controlFill))
                        .overlay(Capsule(style: .continuous).strokeBorder(Color(hex: "2E2E2E"), lineWidth: 1))
                        .scaleEffect(1.25)
                        .shadow(color: .black.opacity(0.6), radius: 14, y: 8),
                    index: 0
                )
                .position(x: center.x - phoneWidth * 0.5, y: center.y - phoneHeight * 0.3)
            }
        }
    }

    private var phone: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.black)
            .overlay {
                SellFilledImage(name: SellScreenAssets.mountainScreenshot)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .padding(4)
                    .accessibilityHidden(true)
            }
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color(hex: "1E1E1E"), lineWidth: 4))
            .overlay(RoundedRectangle(cornerRadius: 31, style: .continuous).strokeBorder(Color(hex: "2A2A2A"), lineWidth: 1).padding(-1))
            .shadow(color: .black.opacity(0.8), radius: 40, y: 30)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SellScreenCopy.GoHarder.screenshotDescription)
    }

    private func chip(_ content: some View, index: Int) -> some View {
        content.onboardingEntrance(style: .pop, delay: Self.chipDelays[index], duration: 0.4)
    }
}
