import Foundation

/// The ranges, steps and unit conversions behind the height ruler and the weight scale.
///
/// Pure, so the numbers the sheets snap to and the text the rows show are tested without a view.
/// A profile stores centimetres and kilograms whatever unit the climber picked; these convert in
/// and out for display.
enum ProfileMeasures {
    /// 4'0" to 7'6", and the metric range that matches it.
    static let heightInchesRange = 48...90
    static let heightCentimetersRange = 122...229

    /// 70 to 400 lb, and 32 to 181 kg. Metric weight snaps to half a kilogram, so the scale is
    /// counted in half kilograms and a position is always a whole number.
    static let weightPoundsRange = 70...400
    static let weightHalfKilogramsRange = 64...362

    /// Where a sheet opens when nothing is set. Opening there never saves it: only Done does.
    static let typicalHeightInches = 68
    static let typicalHeightCentimeters = 173
    static let typicalWeightPounds = 160
    static let typicalWeightHalfKilograms = 140

    private static let centimetersPerInch = 2.54
    private static let kilogramsPerPound = 0.453592

    // MARK: Height

    static func centimeters(inches: Int) -> Double {
        Double(inches) * centimetersPerInch
    }

    static func inches(centimeters: Double) -> Int {
        clamp(Int((centimeters / centimetersPerInch).rounded()), to: heightInchesRange)
    }

    /// The height a stored value shows as on the ruler, in the ruler's own unit.
    static func rulerInches(forCentimeters centimeters: Double?) -> Int {
        centimeters.map(inches(centimeters:)) ?? typicalHeightInches
    }

    static func rulerCentimeters(forCentimeters centimeters: Double?) -> Int {
        centimeters.map { clamp(Int($0.rounded()), to: heightCentimetersRange) } ?? typicalHeightCentimeters
    }

    /// `5'10"` or `178 cm`: the text on the Height row.
    static func heightText(centimeters: Double, system: MeasurementSystem) -> String {
        switch system {
        case .imperial:
            let total = inches(centimeters: centimeters)
            return "\(total / 12)'\(total % 12)\""
        case .metric:
            return "\(Int(centimeters.rounded())) cm"
        }
    }

    /// `5′10″`, drawn with real prime marks for the ruler's big readout.
    static func rulerReadout(inches: Int) -> String {
        "\(inches / 12)\u{2032}\(inches % 12)\u{2033}"
    }

    // MARK: Weight

    static func kilograms(pounds: Int) -> Double {
        Double(pounds) * kilogramsPerPound
    }

    static func kilograms(halfKilograms: Int) -> Double {
        Double(halfKilograms) / 2
    }

    static func pounds(kilograms: Double) -> Int {
        clamp(Int((kilograms / kilogramsPerPound).rounded()), to: weightPoundsRange)
    }

    static func halfKilograms(kilograms: Double) -> Int {
        clamp(Int((kilograms * 2).rounded()), to: weightHalfKilogramsRange)
    }

    static func scalePounds(forKilograms kilograms: Double?) -> Int {
        kilograms.map(pounds(kilograms:)) ?? typicalWeightPounds
    }

    static func scaleHalfKilograms(forKilograms kilograms: Double?) -> Int {
        kilograms.map(halfKilograms(kilograms:)) ?? typicalWeightHalfKilograms
    }

    /// `175 lb` or `79.5 kg`: the text on the Weight row.
    static func weightText(kilograms: Double, system: MeasurementSystem) -> String {
        switch system {
        case .imperial:
            return "\(pounds(kilograms: kilograms)) lb"
        case .metric:
            return "\(kilogramText(Double(halfKilograms(kilograms: kilograms)) / 2)) kg"
        }
    }

    /// `79.4`, one decimal, for the line under the pounds readout. Whole kilograms drop the `.0`.
    static func kilogramText(_ kilograms: Double) -> String {
        let rounded = (kilograms * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    // MARK: Switching units mid-sheet

    /// The same height on the other ruler: the inch count nearest a centimetre count and back.
    static func switchHeight(inches: Int) -> Int {
        clamp(Int(centimeters(inches: inches).rounded()), to: heightCentimetersRange)
    }

    static func switchHeight(centimeters: Int) -> Int {
        inches(centimeters: Double(centimeters))
    }

    static func switchWeight(pounds: Int) -> Int {
        halfKilograms(kilograms: kilograms(pounds: pounds))
    }

    static func switchWeight(halfKilograms: Int) -> Int {
        pounds(kilograms: kilograms(halfKilograms: halfKilograms))
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
