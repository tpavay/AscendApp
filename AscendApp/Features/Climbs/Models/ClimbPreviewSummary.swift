import Foundation

struct ClimbPreviewSummary: Identifiable, Equatable {
    let climb: Climb
    let isCompleted: Bool
    let isActive: Bool

    var id: String { climb.id }
}
