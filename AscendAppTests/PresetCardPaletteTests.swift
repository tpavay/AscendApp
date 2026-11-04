import Foundation
import SwiftUI
import Testing
@testable import AscendApp

struct PresetCardPaletteTests {
    private func palette(_ accent: PresetAccent = .lime, _ background: PresetCardBackground) -> PresetCardPalette {
        PresetCardPalette(accent: accent, background: background)
    }

    @Test
    func aLimeMarkKeepsTheBrandLockupOnEveryCardThatDrawsIt() {
        func treatment(_ accent: PresetAccent, _ background: PresetCardBackground) -> AscendWordmark.Treatment {
            let palette = palette(accent, background)
            return .shareLockup(letters: palette.wordmarkLetters, mark: palette.wordmarkMark)
        }

        #expect(treatment(.lime, .flat(.white)) == .onLight)
        #expect(treatment(.lime, .photo) == .onDark)
        #expect(treatment(.lime, .tower) == .onDark)
        // One colour was already the look on these: an ink A beside ink letters.
        #expect(treatment(.lime, .flat(.accent)) == .mono(Color(share: .ink)))
        #expect(treatment(.lime, .flat(.fade)) == .mono(Color(share: .ink)))
    }

    /// The artwork's A is lime or nothing, so an A in another colour takes the letters' colour.
    @Test
    func aMarkTheArtworkCannotDrawTakesTheLettersColour() {
        let coral = palette(.coral, .photo)
        #expect(coral.wordmarkMark == ShareColor(PresetAccent.coral.hex))
        #expect(
            AscendWordmark.Treatment.shareLockup(letters: coral.wordmarkLetters, mark: coral.wordmarkMark)
                == .mono(Color(share: .paper))
        )
    }

    @Test
    func aDarkBackgroundUsesWhiteTextAndTheAccentAsIs() {
        let dark = palette(.coral, .flat(.black))
        #expect(dark.foreground == .paper)
        #expect(dark.accentText == ShareColor(PresetAccent.coral.hex))
        #expect(dark.wordmarkLetters == .paper)
        #expect(dark.wordmarkMark == ShareColor(PresetAccent.coral.hex))
        #expect(!dark.isLight)
    }

    @Test
    func theWhiteBackgroundSwitchesToInkAndTheDarkAccent() {
        let white = palette(.lime, .flat(.white))
        #expect(white.base == ShareColor(0xF5F5F4))
        #expect(white.foreground == .ink)
        #expect(white.accentText == ShareColor(PresetAccent.lime.onLightHex))
        #expect(white.wordmarkLetters == .ink)
        // Lime A with black letters on white.
        #expect(white.wordmarkMark == ShareColor(PresetAccent.lime.hex))
        #expect(white.isLight)
    }

    @Test
    func theAccentBackgroundPaintsEverythingInInk() {
        let accent = palette(.lime, .flat(.accent))
        #expect(accent.base == ShareColor(PresetAccent.lime.hex))
        #expect(accent.accentText == .ink)
        #expect(accent.wordmarkLetters == .ink)
        #expect(accent.wordmarkMark == .ink)
    }

    @Test
    func aBrightTopSwitchesTheTopRowToInkWhileTheBodyStaysLight() {
        let fade = palette(.lime, .flat(.fade))
        #expect(fade.foreground == .paper)
        #expect(fade.wordmarkLetters == .ink)
        #expect(fade.wordmarkMark == .ink)
        #expect(fade.topSecondary == ShareColor(0x0B0B0B, alpha: 0.7))
    }

    @Test
    func aPhotographOrTheTowerKeepsWhiteTextOverTheScrim() {
        for background in [PresetCardBackground.photo, .tower] {
            let image = palette(.sky, background)
            #expect(image.foreground == .paper)
            #expect(image.wordmarkMark == ShareColor(PresetAccent.sky.hex))
            #expect(background.isImage)
        }
    }

    @Test
    func secondaryTextIsLessOpaqueThanForeground() {
        #expect(palette(.lime, .flat(.black)).secondary.alpha < 1)
        #expect(palette(.lime, .flat(.white)).secondary.alpha < 1)
    }
}
