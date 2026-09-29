import Foundation
@testable import AscendApp

@MainActor
final class FakeLiveClimbBackgroundSession: LiveClimbBackgroundSessionControlling {
    private(set) var isRunning = false
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start(at startedAt: Date) {
        startCallCount += 1
        isRunning = true
    }

    func stop(at endedAt: Date) {
        stopCallCount += 1
        isRunning = false
    }
}
