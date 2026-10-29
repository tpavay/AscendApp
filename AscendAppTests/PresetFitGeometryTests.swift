import CoreGraphics
import Testing
@testable import AscendApp

/// The rules every Presets card uses to keep a number on one line: what closes, shrinks or drops
/// first as figures grow. Pure widths in, widths out.
struct PresetFitGeometryTests {
    private let card: CGFloat = 270

    @Test
    func columnsKeepTheirDesignGapWhileTheyFit() {
        let result = PresetFitGeometry.columns(values: [48, 30, 40], labels: [30, 52, 36], available: card, gap: 22)
        #expect(result.widths == [48, 52, 40])
        #expect(result.gap == 22)
    }

    @Test
    func theGapClosesBeforeAnythingScales() {
        // 140 + 22 * 2 > 150 + ... : the natural row is too wide, but closing the gap is enough.
        let result = PresetFitGeometry.columns(values: [90, 70, 60], labels: [40, 40, 40], available: 240, gap: 22)
        #expect(result.widths == [90, 70, 60])
        #expect(result.gap == 10)
        #expect(result.widths.reduce(0, +) + result.gap * 2 == 240)
    }

    @Test
    func labelsGiveWayBeforeValuesDo() {
        let result = PresetFitGeometry.columns(values: [90, 40, 70], labels: [60, 110, 50], available: 250, gap: 22)
        for (width, value) in zip(result.widths, [90, 40, 70]) {
            #expect(width >= CGFloat(value), "a value lost width before its label did")
        }
        #expect(result.widths[1] < 110, "the long label kept all its width")
        #expect(result.widths[1] >= 110 * PresetFitGeometry.labelFloor)
        #expect(result.gap == PresetFitGeometry.minimumGap)
        #expect(result.widths.reduce(0, +) + result.gap * 2 <= 250 + 0.001)
    }

    @Test
    func theWholeRowScalesTogetherOnlyWhenEvenTheSmallestColumnsAreTooWide() {
        let values: [CGFloat] = [160, 90, 120]
        let labels: [CGFloat] = [40, 40, 40]
        let result = PresetFitGeometry.columns(values: values, labels: labels, available: 270, gap: 22)
        let factors = zip(result.widths, values).map { $0 / $1 }
        #expect(factors.allSatisfy { abs($0 - factors[0]) < 0.0001 }, "columns scaled by different amounts")
        #expect(factors[0] < 1)
        #expect(abs(result.widths.reduce(0, +) + result.gap * 2 - 270) < 0.001)
    }

    @Test(arguments: [0, 1, 2, 3, 4])
    func aRowNeverOverflowsItsWidth(count: Int) {
        let values = (0..<count).map { CGFloat(40 + $0 * 45) }
        let labels = (0..<count).map { CGFloat(90 - $0 * 10) }
        for available in stride(from: CGFloat(60), through: 400, by: 20) {
            let result = PresetFitGeometry.columns(values: values, labels: labels, available: available, gap: 22)
            let used = result.widths.reduce(0, +) + result.gap * CGFloat(max(count - 1, 0))
            #expect(used <= available + 0.001, "\(count) columns use \(used) of \(available)")
        }
    }

    @Test
    func aNumberSitsBesideItsCaptionWhileTheyFit() {
        let placement = PresetFitGeometry.placement(primary: 150, secondary: 100, available: 270, gap: 8, floor: 0.85)
        #expect(placement == .beside(primaryWidth: 150))
    }

    @Test
    func aNumberScalesAHairBeforeItsCaptionMoves() {
        // 160 + 8 + 120 = 288 > 270: the number gives 18 points, 11%, and keeps the line.
        let placement = PresetFitGeometry.placement(primary: 160, secondary: 120, available: 270, gap: 8, floor: 0.85)
        #expect(placement == .beside(primaryWidth: 142))
    }

    @Test
    func theCaptionDropsOnceTheNumberWouldScaleTooFar() {
        let placement = PresetFitGeometry.placement(primary: 180, secondary: 130, available: 270, gap: 8, floor: 0.85)
        #expect(placement == .below)
    }
}
