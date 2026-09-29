@preconcurrency import CoreMotion
import Foundation

/// Resolves Motion & Fitness before a session's countdown, never at GO.
///
/// iOS asks for Motion & Fitness the first time an app starts headphone motion updates, and holds
/// every sample back until the climber answers. Left to recording start, that alert landed at GO
/// on a climber's first session - after the countdown, when they had already turned to the machine
/// or locked the phone - so a first climb run outside the app counted nothing until they came back
/// and answered it. Every later session had the answer already, which is why only the first one
/// failed. Asking here, on the Start tap, puts the alert in front of a climber who is still looking
/// at the screen.
@MainActor
final class HeadphoneMotionAccessGate {
    static let pollInterval: Duration = .milliseconds(200)

    /// How long the answer may stay undetermined while the app stays active before the gate
    /// concludes iOS asked nobody.
    ///
    /// A system alert takes the app out of `.active`, so this window only runs out when no alert
    /// is on screen - it never cuts off a climber who is reading one. Falling through is safe: the
    /// session keeps retrying a refused motion stream instead of failing it.
    static let unpromptedGrace: Duration = .seconds(3)

    private let makeManager: () -> any HeadphoneMotionManaging
    private let authorization: () -> HeadphoneMotionAuthorizationState
    private let sleep: (Duration) async throws -> Void

    /// Mirrors the scene phase. The owning view keeps it current.
    var isAppActive = true

    init(
        makeManager: @escaping () -> any HeadphoneMotionManaging = { CMHeadphoneMotionManager() },
        authorization: @escaping () -> HeadphoneMotionAuthorizationState = HeadphoneMotionAuthorizationState.current,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.makeManager = makeManager
        self.authorization = authorization
        self.sleep = sleep
    }

    /// Returns the climber's answer, asking for it first when iOS has never asked.
    ///
    /// Only an undetermined answer starts motion updates, and those updates exist solely to raise
    /// the alert: they are stopped as soon as the answer lands and every sample is discarded.
    func resolve() async -> HeadphoneMotionAuthorizationState {
        let initial = authorization()
        guard initial == .notDetermined else { return initial }

        let manager = makeManager()
        manager.startDeviceMotionUpdates(to: OperationQueue(), withHandler: Self.discardingHandler())
        defer { manager.stopDeviceMotionUpdates() }

        var unansweredWhileActive: Duration = .zero
        while true {
            do {
                try await sleep(Self.pollInterval)
            } catch {
                return authorization()
            }

            let state = authorization()
            guard state == .notDetermined else { return state }

            unansweredWhileActive = isAppActive ? unansweredWhileActive + Self.pollInterval : .zero
            if unansweredWhileActive >= Self.unpromptedGrace {
                return .notDetermined
            }
        }
    }

    /// Built outside the main actor on purpose: CoreMotion calls it on a background queue, and a
    /// closure formed in a main-actor context traps on that queue's isolation check.
    private nonisolated static func discardingHandler() -> CMHeadphoneMotionManager.DeviceMotionHandler {
        { _, _ in }
    }
}

/// What has to happen before a headphone session's countdown may begin.
enum HeadphoneSessionStartRequirement: Equatable {
    /// Motion & Fitness is off, so nothing could be counted: send the climber to Settings.
    case motionAccessBlocked
    /// No motion-capable headphones are connected.
    case headphonesRequired
    case ready

    /// `headphones` is nil for a flow that does not gate on headphones before its countdown.
    init(
        motionAccess: HeadphoneMotionAuthorizationState,
        headphones: HeadphoneMotionReadiness?
    ) {
        if motionAccess.blocksStepCounting {
            self = .motionAccessBlocked
        } else if let headphones, !headphones.canStartLiveClimb {
            self = .headphonesRequired
        } else {
            self = .ready
        }
    }
}
