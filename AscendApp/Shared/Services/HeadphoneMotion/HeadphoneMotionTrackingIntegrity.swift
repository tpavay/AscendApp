import Foundation

struct HeadphoneMotionTrackingIntegrity: Equatable, Sendable {
    static let recoveryStatusDelay: TimeInterval = 3

    static let verified = HeadphoneMotionTrackingIntegrity(
        currentUnavailableDuration: 0,
        totalUnavailableDuration: 0,
        longestUnavailableDuration: 0,
        interruptionCount: 0
    )

    let currentUnavailableDuration: TimeInterval
    let totalUnavailableDuration: TimeInterval
    let longestUnavailableDuration: TimeInterval
    let interruptionCount: Int

    var isCurrentlyUnavailable: Bool {
        currentUnavailableDuration > 0
    }

    var shouldShowRecoveryStatus: Bool {
        isCurrentlyUnavailable &&
            currentUnavailableDuration >= Self.recoveryStatusDelay
    }

    var unavailableSecondsForDisplay: Int {
        max(Int(currentUnavailableDuration.rounded(.down)), 0)
    }
}
