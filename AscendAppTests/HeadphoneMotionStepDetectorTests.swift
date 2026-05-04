import Foundation
import Testing
@testable import AscendApp

struct HeadphoneMotionStepDetectorTests {
    @Test
    func verticalAccelerationProjectsUserAccelerationOntoGravity() {
        let sample = HeadphoneMotionSample(
            timestamp: 0,
            userAcceleration: HeadphoneMotionVector(x: 0.2, y: 0.4, z: 0.6),
            gravity: HeadphoneMotionVector(x: 0, y: 1, z: 0)
        )

        #expect(HeadphoneMotionStepDetector.verticalAcceleration(from: sample) == 0.4)
    }

    @Test
    func detectsStepLikeVerticalPeaks() {
        let detector = HeadphoneMotionStepDetector()

        for sample in makeSamples(stepCenters: [0.5, 1.2, 1.9]) {
            detector.process(sample)
        }

        #expect(detector.stepCount == 3)
    }

    @Test
    func rejectsPitchRotationHeadNods() {
        let detector = HeadphoneMotionStepDetector()

        for sample in makeSamples(
            stepCenters: [0.5, 1.2, 1.9],
            pitchRotationMagnitude: 4.0
        ) {
            detector.process(sample)
        }

        #expect(detector.stepCount == 0)
    }

    @Test
    func enforcesMinimumTimeBetweenPeaks() {
        let detector = HeadphoneMotionStepDetector()

        for sample in makeSamples(stepCenters: [0.5, 0.68]) {
            detector.process(sample)
        }

        #expect(detector.stepCount == 1)
    }

    private func makeSamples(
        stepCenters: [TimeInterval],
        pitchRotationMagnitude: Double = 0,
        duration: TimeInterval = 2.6,
        sampleRate: Double = 50
    ) -> [HeadphoneMotionSample] {
        let sampleCount = Int(duration * sampleRate)

        return (0..<sampleCount).map { index in
            let timestamp = Double(index) / sampleRate
            let verticalAcceleration = stepCenters.reduce(0.0) { partialResult, center in
                partialResult + stepPulse(at: timestamp, center: center)
            }
            let pitchRotation = stepCenters.contains { abs(timestamp - $0) < 0.16 }
                ? pitchRotationMagnitude
                : 0

            return HeadphoneMotionSample(
                timestamp: timestamp,
                userAcceleration: HeadphoneMotionVector(x: 0, y: 0, z: verticalAcceleration),
                rotationRate: HeadphoneMotionVector(x: pitchRotation, y: 0, z: 0),
                gravity: HeadphoneMotionVector(x: 0, y: 0, z: 1)
            )
        }
    }

    private func stepPulse(at timestamp: TimeInterval, center: TimeInterval) -> Double {
        let halfWidth = 0.16
        let distance = abs(timestamp - center)
        guard distance <= halfWidth else { return 0 }

        return 0.75 * (1 + cos((distance / halfWidth) * .pi)) / 2
    }
}
