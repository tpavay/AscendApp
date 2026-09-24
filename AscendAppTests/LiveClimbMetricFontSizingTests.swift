import CoreGraphics
import CoreText
import Testing

@testable import AscendApp

/// The fixed stat sizes on the Just Me landmark layouts: a slot sized for its widest reading, in
/// tabular digits, so a reading's digit count never changes its size.
@MainActor
struct LiveClimbMetricFontSizingTests {
    @Test("A template turns every digit into an 8 and keeps separators", arguments: [
        ("1,576", "8,888"),
        ("149", "888"),
        ("10:24", "88:88"),
        ("#3", "#8"),
        ("—", "—"),
    ])
    func templateReplacesDigits(value: String, expected: String) {
        #expect(LiveClimbMetricFontSizing.template(for: value) == expected)
    }

    @Test("Measurement uses the bundled Montserrat Bold, not a fallback face")
    func measuresTheRealFace() {
        let font = CTFontCreateWithName(LiveClimbMetricFontSizing.valueFontName as CFString, 20, nil)
        #expect(CTFontCopyPostScriptName(font) as String == "Montserrat-Bold")
    }

    @Test("Digits are tabular: every reading of a given length is exactly as wide as its template")
    func digitsAreTabular() {
        let perDigit = LiveClimbMetricFontSizing.widthPerPoint(of: "8")
        #expect(perDigit > 0)
        for digit in ["0", "1", "4", "7"] {
            #expect(abs(LiveClimbMetricFontSizing.widthPerPoint(of: digit) - perDigit) < 0.0001, "\(digit) is not tabular")
        }
        #expect(abs(LiveClimbMetricFontSizing.widthPerPoint(of: "148") - LiveClimbMetricFontSizing.widthPerPoint(of: "888")) < 0.0001)
        #expect(abs(LiveClimbMetricFontSizing.widthPerPoint(of: "1,576") - LiveClimbMetricFontSizing.widthPerPoint(of: "8,888")) < 0.0001)
    }

    @Test("A fitted size sets the widest reading inside its slot, capped at the scale's size")
    func fittedSizeFitsTheSlot() {
        for width in [60.0, 88.0, 176.0, 190.0] as [CGFloat] {
            let size = LiveClimbMetricFontSizing.fittedSize(for: ["888"], width: width, maximum: 56)
            #expect(size <= 56)
            #expect(size * LiveClimbMetricFontSizing.widthPerPoint(of: "888") <= width, "888 at \(size)pt overflows \(width)pt")
        }

        let both = LiveClimbMetricFontSizing.fittedSize(for: ["88:88", "#888"], width: 150, maximum: 56)
        #expect(both * LiveClimbMetricFontSizing.widthPerPoint(of: "88:88") <= 150)
        #expect(both * LiveClimbMetricFontSizing.widthPerPoint(of: "#888") <= 150)

        #expect(LiveClimbMetricFontSizing.fittedSize(for: ["8"], width: 10_000, maximum: 56) == 56)
        #expect(LiveClimbMetricFontSizing.fittedSize(for: ["888"], width: 0, maximum: 56) == 0)
    }
}
