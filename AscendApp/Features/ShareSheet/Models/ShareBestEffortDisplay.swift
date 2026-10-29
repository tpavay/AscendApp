import Foundation

/// What a Presets card says about the climb's best efforts.
///
/// None earned, or the chip switched off: nothing. One earned: its line, since a count of one says
/// nothing. Several: the real count, one per measure, until the climber picks a single effort to
/// show as its line instead.
enum ShareBestEffortDisplay: Equatable, Sendable {
    case none
    case count(Int)
    case line(ShareSheetSubject.BestEffort)

    static func resolve(
        efforts: [ShareSheetSubject.BestEffort],
        isOn: Bool,
        pickedID: String?
    ) -> ShareBestEffortDisplay {
        guard isOn, let first = efforts.first else { return .none }
        if efforts.count == 1 { return .line(first) }
        if let pickedID, let picked = efforts.first(where: { $0.id == pickedID }) {
            return .line(picked)
        }
        return .count(efforts.count)
    }
}
