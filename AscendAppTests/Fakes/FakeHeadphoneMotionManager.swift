@preconcurrency import CoreMotion
import Foundation
import os
@testable import AscendApp

/// Stands in for `CMHeadphoneMotionManager`, which reports no headphone motion on a simulator.
///
/// CoreMotion drives its real counterpart from background queues, so every field sits behind a lock.
final class FakeHeadphoneMotionManager: HeadphoneMotionManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var _isDeviceMotionActive = false
    private var _isConnectionStatusActive = false
    private var _startDeviceMotionCallCount = 0
    private var _stopDeviceMotionCallCount = 0
    private var handler: CMHeadphoneMotionManager.DeviceMotionHandler?

    weak var delegate: (any CMHeadphoneMotionManagerDelegate)?
    let isDeviceMotionAvailable = true

    var isDeviceMotionActive: Bool {
        lock.withLock { _isDeviceMotionActive }
    }

    var isConnectionStatusActive: Bool {
        lock.withLock { _isConnectionStatusActive }
    }

    var startDeviceMotionCallCount: Int {
        lock.withLock { _startDeviceMotionCallCount }
    }

    var stopDeviceMotionCallCount: Int {
        lock.withLock { _stopDeviceMotionCallCount }
    }

    func startDeviceMotionUpdates(
        to queue: OperationQueue,
        withHandler handler: @escaping CMHeadphoneMotionManager.DeviceMotionHandler
    ) {
        lock.withLock {
            _isDeviceMotionActive = true
            _startDeviceMotionCallCount += 1
            self.handler = handler
        }
    }

    func stopDeviceMotionUpdates() {
        lock.withLock {
            _isDeviceMotionActive = false
            _stopDeviceMotionCallCount += 1
        }
    }

    func startConnectionStatusUpdates() {
        lock.withLock { _isConnectionStatusActive = true }
    }

    func stopConnectionStatusUpdates() {
        lock.withLock { _isConnectionStatusActive = false }
    }

    /// Delivers a stream error the way CoreMotion does, through the latest update handler.
    func deliver(error: CMError) {
        let handler = lock.withLock { self.handler }
        handler?(nil, NSError(domain: CMErrorDomain, code: Int(error.rawValue)))
    }
}

/// A thread-safe, settable Motion & Fitness answer.
final class FakeMotionAuthorization: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<HeadphoneMotionAuthorizationState>

    init(_ state: HeadphoneMotionAuthorizationState) {
        lock = OSAllocatedUnfairLock(initialState: state)
    }

    var state: HeadphoneMotionAuthorizationState {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}
