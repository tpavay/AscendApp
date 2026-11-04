import Foundation
import SwiftUI
import Testing
@testable import AscendApp

struct PresetPreferencesTests {
    private func makeStore() -> PresetPreferencesStore {
        let suite = "PresetPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PresetPreferencesStore(defaults: defaults)
    }

    @Test
    func theDefaultsAreBlackClassicBoldLimeWithTimePaceRankAndBestEfforts() {
        let defaults = PresetPreferences.defaults
        #expect(defaults.layout == .classic)
        #expect(defaults.background == .black)
        #expect(defaults.font == .bold)
        #expect(defaults.accent == .lime)
        #expect(defaults.stats == [.time, .stepsPerMinute, .rank, .bestEfforts])
    }

    @Test
    func choicesRoundTripThroughTheStore() {
        let store = makeStore()
        var preferences = PresetPreferences.defaults
        preferences.layout = .grid
        preferences.background = .aurora
        preferences.font = .mono
        preferences.accent = .coral
        preferences.toggle(.floors)
        preferences.toggle(.rank)
        store.save(preferences)

        #expect(store.load() == preferences)
    }

    @Test
    func nothingStoredLoadsTheDefaultsAndResetReturnsThem() {
        let store = makeStore()
        #expect(store.load() == .defaults)

        var preferences = PresetPreferences.defaults
        preferences.font = .serif
        store.save(preferences)
        store.reset()
        #expect(store.load() == .defaults)
    }

    @Test
    func oneUnrecognisedValueKeepsTheRestOfTheChoices() throws {
        let json = #"{"layout":"warp","background":"stairs","font":"mono","accent":"sky","stats":["time","floors","gone"]}"#
        let decoded = try JSONDecoder().decode(PresetPreferences.self, from: Data(json.utf8))

        #expect(decoded.layout == .classic)
        #expect(decoded.background == .stairs)
        #expect(decoded.font == .mono)
        #expect(decoded.accent == .sky)
        #expect(decoded.stats == [.time, .floors])
    }

    @Test
    func togglingAStatFlipsIt() {
        var preferences = PresetPreferences.defaults
        #expect(preferences.isOn(.time))
        preferences.toggle(.time)
        #expect(!preferences.isOn(.time))
        preferences.toggle(.time)
        #expect(preferences.isOn(.time))
    }

    @Test
    func theStickerStyleDefaultsAndRoundTrips() {
        let suite = "StickerStyleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = StickerStyleStore(defaults: defaults)

        #expect(store.load() == StickerStyle(font: .bold, color: .white, shadow: .soft))
        var style = StickerStyle.defaults
        style.font = .serif
        style.color = .black
        style.shadow = .outline
        store.save(style)
        #expect(store.load() == style)
    }

    @Test
    func aStickerColorPicksTheWordmarkMarkForItsBackdrop() {
        #expect(StickerStyle.Color.white.wordmarkMarkHex == 0x86D30A)
        #expect(StickerStyle.Color.black.wordmarkMarkHex == 0x86D30A)
        for color in [StickerStyle.Color.lime, .coral, .sky] {
            #expect(color.wordmarkMarkHex == 0xFFFFFF)
        }
    }

    /// The brand artwork carries the lime A itself, so white and black stickers keep theirs. The
    /// coloured stickers tint the A white and the letters the sticker's colour.
    @Test
    func aStickerColorPicksTheWordmarkTreatmentForItsBackdrop() {
        var white = StickerStyle.defaults
        white.color = .white
        var black = StickerStyle.defaults
        black.color = .black
        #expect(StickerInk(style: white).wordmark == .onDark)
        #expect(StickerInk(style: black).wordmark == .onLight)
        for color in [StickerStyle.Color.lime, .coral, .sky] {
            var style = StickerStyle.defaults
            style.color = color
            #expect(StickerInk(style: style).wordmark == .twoColour(mark: Color(shareHex: 0xFFFFFF), letters: Color(shareHex: color.hex)))
        }
    }
}
