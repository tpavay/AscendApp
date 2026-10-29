import Foundation
import Testing
@testable import AscendApp

struct PresetCardModelTests {
    private func model(
        _ subject: ShareSheetSubject = .fixture(),
        preferences: PresetPreferences = .defaults,
        layout: PresetLayout = .classic,
        background: PresetCardBackground = .flat(.black),
        picked: String? = nil
    ) -> PresetCardModel {
        PresetCardModel(
            subject: subject,
            preferences: preferences,
            layout: layout,
            background: background,
            pickedBestEffortID: picked,
            copyYear: 2027
        )
    }

    @Test
    func theDefaultRowIsTimePaceAndRank() {
        let card = model()
        #expect(card.stats.map(\.stat) == [.time, .stepsPerMinute, .rank])
        #expect(card.stats.map(\.value) == ["1:02:50", "79.6", "#7"])
        #expect(card.stats.last?.label == "RANK / 64")
    }

    @Test
    func floorsAndHeartRateAppearOnlyWhenOnAndTheClimbHasThem() {
        var preferences = PresetPreferences.defaults
        preferences.toggle(.floors)
        preferences.toggle(.averageHeartRate)

        #expect(model(preferences: preferences).stats.map(\.stat) == [.time, .stepsPerMinute, .floors, .averageHeartRate, .rank])

        let bare = ShareSheetSubject.fixture(floorsText: nil, averageHeartRate: nil)
        #expect(model(bare, preferences: preferences).stats.map(\.stat) == [.time, .stepsPerMinute, .rank])
    }

    @Test
    func noRankMeansNoRankColumnEvenWithTheStatOn() {
        let subject = ShareSheetSubject.fixture(rank: nil)
        #expect(model(subject).stats.map(\.stat) == [.time, .stepsPerMinute])
    }

    @Test
    func theMinimalLineJoinsStepsAndTheSwitchedOnStats() {
        #expect(model().minimalLine == "5,004 steps · 1:02:50 · 79.6 spm · #7 of 64")
    }

    @Test
    func theGridShowsAtMostThreeStatsBesideSteps() {
        var preferences = PresetPreferences.defaults
        preferences.toggle(.floors)
        preferences.toggle(.averageHeartRate)
        #expect(model(preferences: preferences).gridStats.count == 3)
    }

    @Test
    func bestEffortsNeverBecomeARowColumn() {
        let subject = ShareSheetSubject.fixture(bestEfforts: [ShareSheetSubject.effort("a"), ShareSheetSubject.effort("b")])
        let card = model(subject)
        #expect(!card.stats.map(\.stat).contains(.bestEfforts))
        #expect(card.bestEffort == .count(2))
        #expect(card.hasBestEffortBadge)
    }

    @Test
    func aSeasonalBackgroundReplacesTheClimbLabelWithItsCaption() {
        #expect(model().label == "JUST CLIMB")
        #expect(model(background: .seasonal(.confetti)).label == "FIRST CLIMB OF 2027")
        #expect(model(background: .seasonal(.snowfall)).label == "SLEIGHED IT")
    }

    @Test
    func theAvailableStatsFollowWhatTheClimbHas() {
        let full = PresetCardModel.availableStats(for: .fixture(bestEfforts: [ShareSheetSubject.effort("a")]))
        #expect(full == [.time, .stepsPerMinute, .floors, .averageHeartRate, .rank, .bestEfforts])

        let bare = PresetCardModel.availableStats(for: .fixture(floorsText: nil, averageHeartRate: nil, rank: nil))
        #expect(bare == [.time, .stepsPerMinute])
    }

    @Test
    func theLayoutsAvailableFollowRankAndSplits() {
        #expect(PresetLayout.available(hasRank: true, rankStatOn: true, hasSplits: true) == PresetLayout.allCases)
        #expect(!PresetLayout.available(hasRank: true, rankStatOn: false, hasSplits: true).contains(.rank))
        #expect(!PresetLayout.available(hasRank: true, rankStatOn: false, hasSplits: true).contains(.curve))
        #expect(!PresetLayout.available(hasRank: false, rankStatOn: true, hasSplits: false).contains(.curve))
        let noSplits = PresetLayout.available(hasRank: true, rankStatOn: true, hasSplits: false)
        #expect(!noSplits.contains(.splits) && !noSplits.contains(.splitTable))
        #expect(PresetLayout.available(hasRank: false, rankStatOn: true, hasSplits: false).first == .classic)
    }
}
