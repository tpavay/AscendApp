import Foundation

enum ClimbHomeCardState: Equatable {
    case neverClimbed(totalClimbs: Int)
    case inactive(CompletedClimbSummary)
}
