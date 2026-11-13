import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// The kit on screen: the flow with the real header, wordmark and buttons, at the smallest
/// phone Ascend supports and at an accessibility text size. Photographs are written only when
/// `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingV3KitEvidenceTests {
    /// iPhone SE (3rd generation), the smallest phone that runs iOS 26.
    private static let smallestPhone = CGSize(width: 375, height: 667)

    private func coordinator(startingAt step: OnboardingV3Step = .welcome, advancing taps: Int = 0) -> OnboardingV3Coordinator {
        let suite = "onboarding-v3-evidence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(store: PreAuthOnboardingStore(userDefaults: defaults), startingAt: step, now: everyTapAfterTheTransition())
        for _ in 0..<taps { coordinator.advance() }
        return coordinator
    }

    @Test
    func theWelcomeShowsTheRealWordmarkAndItsTwoActions() async throws {
        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator()),
            size: Self.smallestPhone,
            settle: .turns(30)
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("ascend"), "the wordmark is labelled Ascend: \(copy)")
            #expect(copy.contains("get started"), "\(copy)")
            #expect(copy.contains("already have an account? sign in"), "\(copy)")
            #expect(!copy.contains("onboarding progress"), "01 has no bar: \(copy)")
            try screen.photograph(named: "onboarding-v3-welcome-se")
        }
    }

    /// The bar for 02 ends at 38 percent: lime fill under the first 38 percent of the track and the
    /// dark track after it.
    @Test
    func theProgressBarFillsToItsStepsValueOnTheDesignsColours() async throws {
        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator(advancing: 1)),
            size: Self.smallestPhone,
            settle: .turns(40)
        ) { screen in
            _ = try await screen.copy()
            let bar = try #require(try await screen.frame(ofElementLabelled: "Onboarding progress"))
            #expect(bar.height >= 5 && bar.height <= 7, "6 pt tall: \(bar)")

            let y = bar.midY
            let filled = try screen.color(at: CGPoint(x: bar.minX + bar.width * 0.2, y: y))
            let empty = try screen.color(at: CGPoint(x: bar.minX + bar.width * 0.7, y: y))
            #expect(filled.green > 140 && filled.red < 190 && filled.blue < 90, "lime fill: \(filled)")
            #expect(empty.isClose(to: RGBA(red: 0x26, green: 0x26, blue: 0x26, alpha: 255), tolerance: 12), "track: \(empty)")

            let copy = try await screen.copy()
            #expect(copy.contains("back"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-go-harder-se")
        }
    }

    @Test
    func theSkipAndTheCloseVariantRender() async throws {
        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator(startingAt: .profileSetup)),
            size: Self.smallestPhone,
            settle: .turns(30)
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("skip"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-climber-card-se")
        }

        try await RenderedScreen.host(
            OnboardingProgressHeader(onClose: {}).background(Color.black),
            size: CGSize(width: 375, height: 120),
            settle: .turns(12)
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("close"), "\(copy)")
            #expect(!copy.contains("onboarding progress"), "the close variant has no bar: \(copy)")
        }
    }

    @Test
    func everyLabelStaysReachableAtAnAccessibilityTextSize() async throws {
        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator(startingAt: .healthConnect))
                .environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(30)
        ) { screen in
            let recognized = try await screen.recognizedText(scale: 2).lowercased()
            let copy = try await screen.copy()
            #expect(copy.contains("connect apple health"), "\(copy)")
            #expect(copy.contains("skip"), "\(copy)")
            #expect(recognized.contains("connect apple"), "legible, not just in the tree: \(recognized)")
            try screen.photograph(named: "onboarding-v3-health-connect-se-accessibility3")
        }
    }

    private func hostHeadline(
        _ headline: OnboardingHeadline,
        size: CGSize = CGSize(width: 390, height: 300),
        _ body: @MainActor (HostedScreen) async throws -> Void
    ) async throws {
        try await RenderedScreen.host(
            VStack(spacing: 0) {
                headline
                Spacer(minLength: 0)
            }
            .padding(24)
            .background(Color.black)
            .environment(\.dynamicTypeSize, .large),
            size: size,
            settle: .turns(12),
            body
        )
    }

    /// White on the lead and the board's accent on the closing line, one 0.96 em line apart. Both
    /// lines are capitals, so the distance between their ink tops is the line height.
    @Test(arguments: [
        (OnboardingHeadline.Accent.lime, RGBA(red: 0x86, green: 0xD3, blue: 0x0A, alpha: 255)),
        (OnboardingHeadline.Accent.gold, RGBA(red: 0xD4, green: 0xAF, blue: 0x37, alpha: 255)),
        (OnboardingHeadline.Accent.orange, RGBA(red: 0xF0, green: 0xA0, blue: 0x50, alpha: 255))
    ])
    func aHeadlineDrawsItsClosingLineInTheAccentAtTheDesignsLeading(accent: OnboardingHeadline.Accent, ink: RGBA) async throws {
        try await hostHeadline(OnboardingHeadline(["See yourself"], accentLines: ["get better."], accent: accent)) { screen in
            try screen.withPixels(scale: 2) { pixels in
                let lead = try #require(pixels.bounds { $0.isNearWhite })
                let closing = try #require(pixels.bounds { $0.isClose(to: ink) })

                #expect(lead.maxY <= closing.minY + 1, "white stays on the lead: \(lead) \(closing)")
                #expect(abs((closing.minY - lead.minY) - 34 * 0.96) <= 1.5, "\(lead) \(closing)")
            }
        }
    }

    @Test
    func aHeadlineOfOnlyAccentLinesHasNoWhite() async throws {
        let lime = RGBA(red: 0x86, green: 0xD3, blue: 0x0A, alpha: 255)
        try await hostHeadline(OnboardingHeadline([], accentLines: ["Get better."])) { screen in
            try screen.withPixels { pixels in
                #expect(pixels.bounds { $0.isClose(to: lime) } != nil)
                #expect(pixels.bounds { $0.isNearWhite } == nil)
            }
        }
    }

    @Test
    func aHeadlineWithNoAccentLinesIsAllWhite() async throws {
        let lime = RGBA(red: 0x86, green: 0xD3, blue: 0x0A, alpha: 255)
        try await hostHeadline(OnboardingHeadline(["Get better."])) { screen in
            try screen.withPixels { pixels in
                #expect(pixels.bounds { $0.isNearWhite } != nil)
                #expect(pixels.bounds { $0.isClose(to: lime) } == nil)
            }
        }
    }

    /// The welcome headline holds one line each on both phones, between the 24 pt margins.
    @Test(arguments: [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874)])
    func theWelcomeHeadlineHoldsOneLineEachOnBothPhones(size: CGSize) async throws {
        let fontSize = OnboardingWelcomeScreen.headlineSize(screenWidth: size.width)
        try await hostHeadline(
            OnboardingHeadline(
                SellScreenCopy.Welcome.headlineLead,
                accentLines: SellScreenCopy.Welcome.headlineAccent,
                size: fontSize
            ),
            size: size
        ) { screen in
            try screen.withPixels(scale: 2) { pixels in
                let lead = try #require(pixels.bounds { $0.isNearWhite })
                let closing = try #require(pixels.bounds { $0.isClose(to: RGBA(red: 0x86, green: 0xD3, blue: 0x0A, alpha: 255)) })
                #expect(lead.minX >= 23 && lead.maxX <= size.width - 23, "\(lead)")
                #expect(closing.minX >= 23 && closing.maxX <= size.width - 23, "\(closing)")
                #expect(lead.height <= fontSize * 1.05, "CONGRATULATIONS, broke across lines: \(lead)")
                #expect(closing.height <= fontSize * 1.05, "YOU'RE ON YOUR WAY broke across lines: \(closing)")
                #expect(lead.width >= (size.width - 48) * 0.8, "shrunk far below its width: \(lead)")
            }
            try screen.photograph(named: "onboarding-v3-headline-welcome-\(Int(size.height))")
        }
    }

    /// The primary action keeps its label whole on the smallest phone at the largest text size: one
    /// line, all of it, inside the button.
    @Test
    func thePrimaryButtonShrinksItsLabelRatherThanBreakAWordAtTheLargestTextSize() async throws {
        try await RenderedScreen.host(
            VStack(spacing: 0) {
                Button("Continue") {}
                    .buttonStyle(.onboardingPrimary)
                Spacer(minLength: 0)
            }
            .padding(24)
            .background(Color.black)
            .environment(\.dynamicTypeSize, .accessibility5),
            size: Self.smallestPhone,
            settle: .turns(12)
        ) { screen in
            let isLime: (RGBA) -> Bool = { $0.green > 170 && $0.blue < 60 }
            let isInk: (RGBA) -> Bool = { $0.luminance < 40 }
            try screen.withPixels(scale: 2) { pixels in
                let button = try #require(pixels.bounds(where: isLime))
                let label = try #require(pixels.bounds(in: button.insetBy(dx: 18, dy: 4), where: isInk))

                var blankRows = 0
                for y in stride(from: label.minY, to: label.maxY, by: 1) {
                    let row = CGRect(x: label.minX, y: y, width: label.width, height: 1)
                    if pixels.count(in: row, where: isInk) == 0 { blankRows += 1 }
                }
                #expect(blankRows == 0, "the label broke in two: \(blankRows) empty rows inside \(label)")
            }
            // Legibility is the contract here: the last letters are drawn, not truncated away.
            let drawn = try await screen.recognizedText(scale: 2).uppercased()
            #expect(drawn.contains("CONTINUE"), "\(drawn)")
        }
    }

    /// A word wider than the screen at a large text size shrinks. It never breaks across two lines,
    /// and neither does any line the design wrote as one.
    @Test(arguments: [
        (["Welcome"], [String]()),
        (["See yourself"], ["get better."])
    ])
    func aHeadlineShrinksRatherThanBreakAWordAtTheLargestTextSize(lead: [String], accent: [String]) async throws {
        try await RenderedScreen.host(
            VStack(spacing: 0) {
                OnboardingHeadline(lead, accentLines: accent, size: 46)
                Spacer(minLength: 0)
            }
            .padding(24)
            .background(Color.black)
            .environment(\.dynamicTypeSize, .accessibility5),
            size: Self.smallestPhone,
            settle: .turns(12)
        ) { screen in
            try screen.withPixels(scale: 2) { pixels in
                let ink = try #require(pixels.bounds { $0.isNearWhite })
                #expect(ink.minX >= 23 && ink.maxX <= 352, "\(ink)")

                var blankRows = 0
                for y in stride(from: ink.minY, to: ink.maxY, by: 1) {
                    let row = CGRect(x: ink.minX, y: y, width: ink.width, height: 1)
                    if pixels.count(in: row, where: { $0.isNearWhite }) == 0 { blankRows += 1 }
                }
                #expect(blankRows == 0, "the white line broke in two: \(blankRows) empty rows inside \(ink)")
            }
        }
    }

    /// The A and the letters each hold the colour the palette asks for, read on either side of the
    /// gap in the artwork, on a grey that none of them match.
    @Test(arguments: [
        ("coral accent on a dark card", PresetCardPalette(accent: .coral, background: .flat(.black)).wordmarkMark, PresetCardPalette(accent: .coral, background: .flat(.black)).wordmarkLetters),
        ("sky accent on a photo card", PresetCardPalette(accent: .sky, background: .photo).wordmarkMark, PresetCardPalette(accent: .sky, background: .photo).wordmarkLetters),
        ("white sticker", ShareColor(StickerStyle.Color.white.wordmarkMarkHex), ShareColor(StickerStyle.Color.white.hex)),
        ("lime sticker", ShareColor(StickerStyle.Color.lime.wordmarkMarkHex), ShareColor(StickerStyle.Color.lime.hex))
    ])
    func aShareLockupDrawsItsAAndItsLettersInTheirOwnColours(name: String, mark: ShareColor, letters: ShareColor) async throws {
        func rgba(_ color: ShareColor) -> RGBA {
            RGBA(
                red: UInt8((color.hex >> 16) & 0xFF),
                green: UInt8((color.hex >> 8) & 0xFF),
                blue: UInt8(color.hex & 0xFF),
                alpha: 255
            )
        }

        try await RenderedScreen.host(
            ZStack {
                Color(white: 0.5).ignoresSafeArea()
                AscendWordmark(height: 60, treatment: .shareLockup(letters: letters, mark: mark))
            },
            size: CGSize(width: 390, height: 200),
            settle: .turns(12)
        ) { screen in
            let lockup = try #require(try await screen.frame(ofElementLabelled: "Ascend"))
            let edge = lockup.minX + lockup.width * 446 / 1815
            let markSide = CGRect(x: lockup.minX, y: lockup.minY, width: edge - lockup.minX, height: lockup.height)
            let letterSide = CGRect(x: edge, y: lockup.minY, width: lockup.maxX - edge, height: lockup.height)

            try screen.withPixels(scale: 2) { pixels in
                #expect(pixels.count(in: markSide) { $0.isClose(to: rgba(mark)) } > 200, "\(name): the A")
                #expect(pixels.count(in: markSide) { $0.isClose(to: rgba(letters)) } == 0, "\(name): no letter colour on the A")
                #expect(pixels.count(in: letterSide) { $0.isClose(to: rgba(letters)) } > 200, "\(name): the letters")
                #expect(pixels.count(in: letterSide) { $0.isClose(to: rgba(mark)) } == 0, "\(name): no A colour on the letters")
            }
        }
    }

    @Test
    func theSignedOutHoldIsTheWordmarkOnBlackAndNothingElse() async throws {
        try await RenderedScreen.host(
            SignedOutHoldView(),
            size: CGSize(width: 390, height: 844),
            settle: .turns(12)
        ) { screen in
            let wordmark = try #require(try await screen.frame(ofElementLabelled: "Ascend"))
            #expect(abs(wordmark.midX - 195) < 1, "\(wordmark)")
            #expect(try await screen.copy().contains("ascend"))
            try screen.photograph(named: "onboarding-v3-signed-out-hold")
        }
    }

    @Test
    func theWordmarkKeepsTheBrandProportionsAtEveryHeight() async throws {
        try await RenderedScreen.host(
            VStack(alignment: .leading, spacing: 20) {
                AscendWordmark(height: 22, treatment: .onDark)
                AscendWordmark(height: 22, treatment: .mono(.white))
                AscendWordmark(height: 36, treatment: .onDark)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black),
            size: CGSize(width: 375, height: 220),
            settle: .turns(12)
        ) { screen in
            let wordmark = try #require(try await screen.frame(ofElementLabelled: "Ascend"))
            // 1815 x 413 artwork: a 22 pt A makes a lockup about 96.7 pt wide.
            #expect(abs(wordmark.height - 22) < 1, "\(wordmark)")
            #expect(abs(wordmark.width - 22 * 1815 / 413) < 2, "\(wordmark)")
            try screen.photograph(named: "onboarding-v3-wordmarks")
        }
    }
}
