import CoreMotion
import Foundation
import Observation

enum HeadphoneMotionReadiness: Equatable {
    case ready
    case unavailable

    var canStartLiveClimb: Bool {
        self == .ready
    }
}

@MainActor
@Observable
final class HeadphoneMotionReadinessService {
    static let shared = HeadphoneMotionReadinessService()

    private let motionManager = CMHeadphoneMotionManager()

    private(set) var readiness: HeadphoneMotionReadiness = .unavailable

    private init() {
        refresh()
    }

    func refresh() {
        readiness = motionManager.isDeviceMotionAvailable ? .ready : .unavailable
    }
}
