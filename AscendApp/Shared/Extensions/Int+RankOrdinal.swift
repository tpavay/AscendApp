import Foundation

extension Int {
    /// The placing spelled the way every Ascend surface spells one: `1st`, `2nd`.
    ///
    /// Shared rather than owned by any one surface, because the completion
    /// hero, the live race panel and the Live Activity all state placings and a
    /// second spelling of the same number would read as a second measurement.
    var rankOrdinalText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
