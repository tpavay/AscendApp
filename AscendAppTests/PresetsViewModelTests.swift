import Foundation
import Testing
import UIKit
@testable import AscendApp

@MainActor
struct PresetsViewModelTests {
    private func makeStore() -> PresetPreferencesStore {
        let suite = "PresetsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PresetPreferencesStore(defaults: defaults)
    }

    private func make(
        _ subject: ShareSheetSubject = .fixture(),
        hasTower: Bool = false,
        store: PresetPreferencesStore? = nil,
        now: Date = Date(timeIntervalSince1970: 1_792_000_000)
    ) -> PresetsViewModel {
        PresetsViewModel(
            subject: subject,
            hasTower: hasTower,
            store: store ?? makeStore(),
            clock: { now }
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test
    func aFreshClimberOpensOnBlackClassic() {
        let model = make()
        #expect(model.currentLayout == .classic)
        #expect(model.background == .flat(.black))
        #expect(model.layouts == PresetLayout.allCases)
    }

    @Test
    func aLandmarkClimbAlwaysOpensOnItsTower() {
        let model = make(.fixture(kind: .landmark), hasTower: true)
        #expect(model.background == .tower)
    }

    @Test
    func theTowerAndAPhotoAreNeverRemembered() {
        let store = makeStore()
        let model = make(.fixture(kind: .landmark), hasTower: true, store: store)
        model.selectBackground(.stairs)
        #expect(model.background == .flat(.stairs))

        // The next climb opens on its tower again but remembers the last flat background.
        let next = make(.fixture(kind: .landmark), hasTower: true, store: store)
        #expect(next.background == .tower)
        next.selectBackground(.black)
        let afterwards = make(.fixture(), store: store)
        #expect(afterwards.background == .flat(.black))
        #expect(store.load().background == .black)
    }

    @Test
    func choicesPersistAcrossViewModels() {
        let store = makeStore()
        let first = make(store: store)
        first.selectBackground(.aurora)
        first.setFont(.mono)
        first.setAccent(.coral)
        first.toggle(.floors)
        first.select(layout: .grid)

        let second = make(store: store)
        #expect(second.preferences.background == .aurora)
        #expect(second.preferences.font == .mono)
        #expect(second.preferences.accent == .coral)
        #expect(second.preferences.isOn(.floors))
        #expect(second.currentLayout == .grid)
    }

    @Test
    func aSavedRankLayoutWithNoRankFallsBackToClassic() {
        let store = makeStore()
        var saved = PresetPreferences.defaults
        saved.layout = .rank
        store.save(saved)

        #expect(make(.fixture(rank: nil), store: store).currentLayout == .classic)
        #expect(make(.fixture(), store: store).currentLayout == .rank)
    }

    @Test
    func aSavedSplitLayoutWithNoSplitsFallsBackToClassic() {
        let store = makeStore()
        var saved = PresetPreferences.defaults
        saved.layout = .splitTable
        store.save(saved)
        #expect(make(.fixture(splits: []), store: store).currentLayout == .classic)
    }

    @Test
    func turningRankOffRemovesTheRankLayoutsAndMovesOffThem() {
        let model = make()
        model.select(layout: .curve)
        #expect(model.currentLayout == .curve)

        model.toggle(.rank)
        #expect(!model.layouts.contains(.rank))
        #expect(!model.layouts.contains(.curve))
        #expect(model.currentLayout == .classic)
    }

    @Test
    func swipingStopsAtBothEnds() {
        let model = make()
        model.swipe(by: -1)
        #expect(model.currentLayout == .classic)
        for _ in 0..<20 { model.swipe(by: 1) }
        #expect(model.currentLayout == .minimal)
    }

    @Test
    func theCaptionReadsSwipeForMoreOnTheFirstLayoutThenAPosition() {
        let model = make()
        #expect(model.layoutCaption == "Classic · swipe for more")
        model.swipe(by: 1)
        #expect(model.layoutCaption == "Rank · 2 of 9")
    }

    @Test
    func theShownCountIsStepsPlusEverySwitchedOnStatTheClimbHas() {
        // Steps, Time, SPM, Rank.
        #expect(make().shownStatCount == 4)

        let withEfforts = make(.fixture(bestEfforts: [ShareSheetSubject.effort("a")]))
        // Best efforts counts only when earned: Steps, Time, SPM, Rank, Best efforts.
        #expect(withEfforts.shownStatCount == 5)

        let bare = make(.fixture(rank: nil))
        #expect(bare.shownStatCount == 3)
    }

    @Test
    func resetReturnsTheDefaultsAndForgetsThePickedEffort() {
        let model = make(.fixture(bestEfforts: [ShareSheetSubject.effort("a"), ShareSheetSubject.effort("b")]))
        model.setFont(.serif)
        model.selectBackground(.hex)
        model.pickBestEffort("b")
        model.reset()

        #expect(model.preferences == .defaults)
        #expect(model.pickedBestEffortID == nil)
        #expect(model.background == .flat(.black))
    }

    @Test
    func aSeasonalBackgroundIsUsedInItsWindowAndFallsBackToBlackAfterwards() {
        let store = makeStore()
        let december = date(2026, 12, 10)
        let inWindow = make(store: store, now: december)
        inWindow.selectBackground(.dots)
        inWindow.selectSeasonal(.snowfall)
        #expect(inWindow.background == .seasonal(.snowfall))
        #expect(store.load().background == .dots)

        let after = make(store: store, now: date(2027, 2, 10))
        #expect(after.background == .flat(.black))
        #expect(after.seasonalBackgrounds.isEmpty)
    }

    @Test
    func aSeasonalBackgroundOutOfItsWindowCannotBeChosen() {
        let model = make(now: date(2027, 3, 3))
        model.selectSeasonal(.snowfall)
        #expect(model.background == .flat(.black))
        #expect(model.preferences.seasonal == nil)
    }

    @Test
    func pickingAFlatBackgroundLeavesSeasonal() {
        let model = make(now: date(2026, 12, 10))
        model.selectSeasonal(.cocoa)
        model.selectBackground(.dots)
        #expect(model.background == .flat(.dots))
        #expect(model.preferences.seasonal == nil)
    }

    @Test
    func aPickedBestEffortReachesTheCard() {
        let efforts = [ShareSheetSubject.effort("a"), ShareSheetSubject.effort("b"), ShareSheetSubject.effort("c")]
        let model = make(.fixture(bestEfforts: efforts))
        #expect(model.cardModel.bestEffort == .count(3))
        model.pickBestEffort("b")
        #expect(model.cardModel.bestEffort == .line(efforts[1]))
        model.toggle(.bestEfforts)
        #expect(model.cardModel.bestEffort == .none)
    }

    @Test
    func framingAPhotoIsClampedToCoverTheCardAndResetByANewPhoto() {
        let model = make()
        model.selectPhoto(UIImage())
        #expect(model.background == .photo)
        model.frame(scale: 9, offset: CGSize(width: 0.2, height: 0.1))
        #expect(model.artwork.photoScale == 4)
        #expect(model.artwork.photoOffset == CGSize(width: 0.2, height: 0.1))
        model.frame(scale: 0.2, offset: .zero)
        #expect(model.artwork.photoScale == 1)
        model.frame(scale: 1, offset: CGSize(width: 0.3, height: -0.2))
        #expect(model.artwork.photoOffset == .zero, "a photo at fit scale was dragged off the card")
        model.frame(scale: 2, offset: CGSize(width: 0.9, height: -0.9))
        #expect(model.artwork.photoOffset == CGSize(width: 0.5, height: -0.5), "the photo was panned past its own edge")
        model.selectPhoto(UIImage())
        #expect(model.artwork.photoScale == 1)
        #expect(model.artwork.photoOffset == .zero)
    }
}
