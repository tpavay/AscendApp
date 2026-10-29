import Foundation

extension ShareSheetSubject {
    /// The population a climb is ranked against, named the way the climber knows it: every Just
    /// Climb, the routine's name, or the landmark's name.
    var stickerFieldName: String {
        switch kind {
        case .justClimb: return "JUST CLIMBS"
        case .routine: return title.uppercased()
        case .landmark: return (landmark?.name ?? title).uppercased()
        }
    }
}
