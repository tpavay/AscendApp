import Foundation

struct RelativeRoutineInterval: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var zone: ClimbZone
    var duration: TimeInterval
    var modifiers: IntervalModifiers

    init(
        id: UUID = UUID(),
        zone: ClimbZone,
        duration: TimeInterval,
        modifiers: IntervalModifiers = .none
    ) {
        self.id = id
        self.zone = zone
        self.duration = duration
        self.modifiers = modifiers
    }
}
