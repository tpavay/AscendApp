@preconcurrency import CoreMotion
import Foundation

/// The slice of `CMHeadphoneMotionManager` Ascend drives, so the permission and recovery paths can
/// be exercised without a pair of headphones: the simulator reports no headphone motion at all.
protocol HeadphoneMotionManaging: AnyObject {
    var isDeviceMotionAvailable: Bool { get }
    var isDeviceMotionActive: Bool { get }
    var isConnectionStatusActive: Bool { get }
    var delegate: (any CMHeadphoneMotionManagerDelegate)? { get set }

    func startDeviceMotionUpdates(
        to queue: OperationQueue,
        withHandler handler: @escaping CMHeadphoneMotionManager.DeviceMotionHandler
    )
    func stopDeviceMotionUpdates()
    func startConnectionStatusUpdates()
    func stopConnectionStatusUpdates()
}

extension CMHeadphoneMotionManager: HeadphoneMotionManaging {}

/// The climber's Motion & Fitness answer, which is what headphone motion is gated on.
enum HeadphoneMotionAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted

    /// Whether the climber has to go to Settings before a single step can be counted.
    var blocksStepCounting: Bool {
        switch self {
        case .denied, .restricted:
            return true
        case .notDetermined, .authorized:
            return false
        }
    }

    init(_ status: CMAuthorizationStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            // Unknown is not a refusal: asking again surfaces whatever iOS now means by it.
            self = .notDetermined
        }
    }

    /// Reads the process-wide answer. Safe from any thread.
    static func current() -> HeadphoneMotionAuthorizationState {
        HeadphoneMotionAuthorizationState(CMHeadphoneMotionManager.authorizationStatus())
    }
}
