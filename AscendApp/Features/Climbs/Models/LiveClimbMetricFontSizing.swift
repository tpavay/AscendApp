import CoreGraphics
import CoreText
import Foundation

/// Sizes a live stat so it never changes size as its digit count does.
///
/// Letting a value shrink to fit (`minimumScaleFactor`) made the Just Me numbers jump as they
/// went from 1 to 2 to 3 digits, which shifted the whole column. Instead each stat is set at one
/// fixed size: the largest at which its widest possible reading - its slot template, every digit
/// an 8 - fits the slot's width in tabular (monospaced) digits. A 7 then sits in the same slot, at
/// the same size, as a 148.
@MainActor
enum LiveClimbMetricFontSizing {
    static let valueFontName = "Montserrat-Bold"

    /// The widest current or average SPM reading a climber produces.
    static let paceTemplate = "888"
    /// The elapsed clock up to 59:59; an hour-long climb's clock falls back to shrinking.
    static let elapsedTemplate = "88:88"
    /// A standing up to #999; a larger rank falls back to shrinking.
    static let rankTemplate = "#888"

    /// A value's widest shape at its length: every digit replaced by 8, the widest numeral in
    /// most faces, so any reading of that length fits. "1,576" becomes "8,888".
    static func template(for value: String) -> String {
        String(value.map { $0.isNumber ? "8" : $0 })
    }

    /// The largest size, capped at `maximum` and rounded down to a half point, at which every
    /// template fits `width` set in the value font with tabular digits.
    static func fittedSize(for templates: [String], width: CGFloat, maximum: CGFloat) -> CGFloat {
        guard width > 0, maximum > 0 else { return 0 }
        var size = maximum
        for template in templates {
            let perPoint = widthPerPoint(of: template)
            guard perPoint > 0 else { continue }
            size = min(size, ((width / (perPoint * safetyMargin)) * 2).rounded(.down) / 2)
        }
        return max(size, 0)
    }

    /// A hair of slack against rounding between CoreText's measure and SwiftUI's layout, so a
    /// template never lands a fraction of a point too wide and trips the shrink fallback.
    private static let safetyMargin: CGFloat = 1.03

    private static var widthPerPointCache: [String: CGFloat] = [:]

    /// The template's typographic width at 1pt. Text width is linear in point size, so one
    /// measurement per template serves every size.
    static func widthPerPoint(of template: String) -> CGFloat {
        if let cached = widthPerPointCache[template] { return cached }

        let measuringSize: CGFloat = 100
        let tabularDigits: [[CFString: Any]] = [[
            kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
            kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector,
        ]]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontDescriptorCreateWithNameAndSize(valueFontName as CFString, measuringSize),
            [kCTFontFeatureSettingsAttribute: tabularDigits] as CFDictionary
        )
        let font = CTFontCreateWithFontDescriptor(descriptor, measuringSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: template,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        ))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) / measuringSize
        widthPerPointCache[template] = width
        return width
    }
}
