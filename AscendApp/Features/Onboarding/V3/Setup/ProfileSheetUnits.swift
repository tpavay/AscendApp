import Foundation

/// The options of a sheet's unit switch, and what picking one does.
struct ProfileSheetUnits {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void
}
