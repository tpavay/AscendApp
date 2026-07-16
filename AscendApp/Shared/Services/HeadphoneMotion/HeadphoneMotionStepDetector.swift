import Foundation

struct HeadphoneMotionStepDetection: Equatable, Sendable {
    let stepCount: Int
    let timestamp: TimeInterval
    let filteredVerticalAcceleration: Double
}

/// Streaming stair-step detector for compatible headphone motion samples.
///
/// This is intentionally pure compute: no Core Motion types, no clocks, no UI state.
/// The owner must call `process(_:)` serially because the filter keeps rolling state.
final class HeadphoneMotionStepDetector {
    static let algorithmVersion = 1

    // 2nd-order Butterworth low-pass filter at 4Hz, assuming a 50Hz input stream.
    private let b0 = 0.046131802093312926
    private let b1 = 0.09226360418662585
    private let b2 = 0.046131802093312926
    private let a1 = -1.3072850288493236
    private let a2 = 0.4918122372225753

    private var verticalInput1 = 0.0
    private var verticalInput2 = 0.0
    private var verticalOutput1 = 0.0
    private var verticalOutput2 = 0.0

    private var pitchInput1 = 0.0
    private var pitchInput2 = 0.0
    private var pitchOutput1 = 0.0
    private var pitchOutput2 = 0.0

    private var recentPitchRotationMagnitudes: [Double] = []
    private let rotationWindowSize = 15

    private var previousFilteredVerticalAcceleration = 0.0
    private var wasRising = false
    private var lastPeakTime: TimeInterval = -1

    private let peakThreshold = 0.15
    private let minimumTimeBetweenPeaks: TimeInterval = 0.3
    private let maximumPitchRotationRate = 1.5

    private(set) var stepCount = 0
    private(set) var currentFilteredVerticalAcceleration = 0.0

    func reset() {
        verticalInput1 = 0
        verticalInput2 = 0
        verticalOutput1 = 0
        verticalOutput2 = 0
        pitchInput1 = 0
        pitchInput2 = 0
        pitchOutput1 = 0
        pitchOutput2 = 0
        recentPitchRotationMagnitudes = []
        previousFilteredVerticalAcceleration = 0
        wasRising = false
        lastPeakTime = -1
        stepCount = 0
        currentFilteredVerticalAcceleration = 0
    }

    @discardableResult
    func process(_ sample: HeadphoneMotionSample) -> HeadphoneMotionStepDetection? {
        let verticalAcceleration = Self.verticalAcceleration(from: sample)
        let filteredVerticalAcceleration = filterVerticalAcceleration(verticalAcceleration)
        let filteredPitchRotation = filterPitchRotation(sample.rotationRate.x)

        recentPitchRotationMagnitudes.append(abs(filteredPitchRotation))
        if recentPitchRotationMagnitudes.count > rotationWindowSize {
            recentPitchRotationMagnitudes.removeFirst()
        }

        currentFilteredVerticalAcceleration = filteredVerticalAcceleration

        let isRising = filteredVerticalAcceleration > previousFilteredVerticalAcceleration
        defer {
            wasRising = isRising
            previousFilteredVerticalAcceleration = filteredVerticalAcceleration
        }

        guard wasRising,
              !isRising,
              previousFilteredVerticalAcceleration > peakThreshold else {
            return nil
        }

        let timeSinceLastPeak = lastPeakTime < 0
            ? Double.infinity
            : sample.timestamp - lastPeakTime
        let maximumRecentPitchRotation = recentPitchRotationMagnitudes.max() ?? 0
        let isNotHeadNod = maximumRecentPitchRotation < maximumPitchRotationRate

        guard timeSinceLastPeak >= minimumTimeBetweenPeaks, isNotHeadNod else {
            return nil
        }

        stepCount += 1
        lastPeakTime = sample.timestamp

        return HeadphoneMotionStepDetection(
            stepCount: stepCount,
            timestamp: sample.timestamp,
            filteredVerticalAcceleration: previousFilteredVerticalAcceleration
        )
    }

    static func verticalAcceleration(from sample: HeadphoneMotionSample) -> Double {
        sample.userAcceleration.x * sample.gravity.x +
            sample.userAcceleration.y * sample.gravity.y +
            sample.userAcceleration.z * sample.gravity.z
    }

    private func filterVerticalAcceleration(_ value: Double) -> Double {
        let filtered = b0 * value +
            b1 * verticalInput1 +
            b2 * verticalInput2 -
            a1 * verticalOutput1 -
            a2 * verticalOutput2

        verticalInput2 = verticalInput1
        verticalInput1 = value
        verticalOutput2 = verticalOutput1
        verticalOutput1 = filtered

        return filtered
    }

    private func filterPitchRotation(_ value: Double) -> Double {
        let filtered = b0 * value +
            b1 * pitchInput1 +
            b2 * pitchInput2 -
            a1 * pitchOutput1 -
            a2 * pitchOutput2

        pitchInput2 = pitchInput1
        pitchInput1 = value
        pitchOutput2 = pitchOutput1
        pitchOutput1 = filtered

        return filtered
    }
}
