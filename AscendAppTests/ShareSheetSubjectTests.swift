import Foundation
import Testing
@testable import AscendApp

struct ShareSheetSubjectTests {
    @Test
    func aRankReadsTopAndBeatPercentFromTheSameFinish() throws {
        let rank = try #require(ShareSheetSubject.Rank(position: 7, field: 64))
        #expect(rank.topPercent == 11)
        #expect(rank.beatPercent == 89)
        #expect(rank.positionText == "7")
        #expect(rank.fieldText == "64")
    }

    @Test
    func lastPlaceBeatNobodyAndAFieldOfOneIsAFirstAscent() throws {
        let last = try #require(ShareSheetSubject.Rank(position: 64, field: 64))
        #expect(last.beatPercent == 0)
        #expect(last.topPercent == 100)

        let alone = try #require(ShareSheetSubject.Rank(position: 1, field: 1))
        #expect(alone.isFirstAscent)
    }

    @Test
    func aTopPercentNeverReadsZero() throws {
        let first = try #require(ShareSheetSubject.Rank(position: 1, field: 5_000))
        #expect(first.topPercent == 1)
    }

    @Test
    func aMissingOrImpossibleRankIsNoRank() {
        #expect(ShareSheetSubject.Rank(position: nil, field: 10) == nil)
        #expect(ShareSheetSubject.Rank(position: 3, field: nil) == nil)
        #expect(ShareSheetSubject.Rank(position: 0, field: 10) == nil)
        #expect(ShareSheetSubject.Rank(position: 3, field: 0) == nil)
        #expect(ShareSheetSubject.Rank(position: 12, field: 10)?.position == 10)
    }

    @Test
    func theCurveAxisNamesTheMeasureTheRankCounted() {
        let landmark = ShareSheetSubject.fixture(kind: .landmark).rankAxis
        #expect(landmark.lower == "SLOWER")
        #expect(landmark.upper == "FASTER")
        for kind in [ShareSheetSubject.Kind.justClimb, .routine] {
            let axis = ShareSheetSubject.fixture(kind: kind).rankAxis
            #expect(axis.lower == "FEWER STEPS")
            #expect(axis.upper == "MORE STEPS")
        }
    }

    @Test
    func splitsFormatTheirOwnText() {
        let split = ShareSheetSubject.Split(index: 6, durationSeconds: 530, steps: 747, stepsPerMinute: 84.6)
        #expect(split.number == "7")
        #expect(split.durationText == "8:50")
        #expect(split.stepsText == "747")
        #expect(split.stepsPerMinuteText == "85")
    }

    @Test
    func theFastestSplitIsTheHighestPace() {
        let subject = ShareSheetSubject.fixture()
        #expect(subject.fastestSplit?.index == 6)
        #expect(subject.hasSplits)
        #expect(!ShareSheetSubject.fixture(splits: []).hasSplits)
    }

    @Test
    func theHeadlineJoinsTimeStepsAndPace() {
        #expect(ShareSheetSubject.fixture().headline == "1:02:50 · 5,004 steps · 79.6 SPM")
    }

    @Test
    func clockTimeDropsTheHourWhenThereIsNone() {
        #expect(ShareSheetFormat.clock(3_770) == "1:02:50")
        #expect(ShareSheetFormat.clock(540) == "9:00")
        #expect(ShareSheetFormat.clock(-4) == "0:00")
    }

    @Test
    func floorsAreStepsDividedBySixteenForAnyStairWork() {
        let workout = Workout(duration: 3_770, steps: 5_004, floors: 0, source: .manual)
        #expect(ShareSheetSubjectBuilder.floorsText(workout: workout, climb: nil) == "313")
    }

    @Test
    func aLandmarkShowsItsBuildingsOwnFloorsScaledToTheAttempt() {
        let workout = Workout(duration: 3_000, steps: 1_576, floors: 0, source: .manual)
        // Empire State: 86 published floors over 1,576 real stairs, so a full climb is 86.
        #expect(ShareSheetSubjectBuilder.floorsText(workout: workout, climb: .preview) == "86")
    }

    @Test
    func noStepsMeansNoFloors() {
        let workout = Workout(duration: 60, steps: 0, floors: 0, source: .manual)
        #expect(ShareSheetSubjectBuilder.floorsText(workout: workout, climb: nil) == nil)
    }

    @Test
    func aLongSeriesDownsamplesEvenlyAndAShortOneIsLeftAlone() {
        let long = (0..<100).map(Double.init)
        let reduced = ShareSheetSubjectBuilder.downsample(long, to: 10)
        #expect(reduced.count == 10)
        #expect(reduced.first == 0)
        #expect(reduced.last == 99)

        let short = [1.0, 2.0, 3.0]
        #expect(ShareSheetSubjectBuilder.downsample(short, to: 10) == short)
    }
}
