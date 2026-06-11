#if DEBUG
import Foundation

struct JourneyStep: Identifiable {
    let journeyId: String
    let index: Int
    let climb: Climb
    let status: JourneyStepStatus

    var id: String {
        "\(journeyId)-\(climb.id)"
    }
}
#endif
