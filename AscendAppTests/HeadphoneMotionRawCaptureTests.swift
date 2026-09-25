import Foundation
import Testing
@testable import AscendApp

struct HeadphoneMotionRawCaptureTests {
    private func makeSample(timestamp: TimeInterval) -> HeadphoneMotionSample {
        HeadphoneMotionSample(
            timestamp: timestamp,
            userAcceleration: HeadphoneMotionVector(x: 0.1, y: 0.2, z: 0.3),
            rotationRate: HeadphoneMotionVector(x: 0.01, y: 0, z: 0),
            gravity: HeadphoneMotionVector(x: 0, y: 0, z: 1)
        )
    }

    private func makeDetection(stepCount: Int, timestamp: TimeInterval) -> HeadphoneMotionStepDetection {
        HeadphoneMotionStepDetection(
            stepCount: stepCount,
            timestamp: timestamp,
            filteredVerticalAcceleration: 0.4
        )
    }

    @Test
    func recordsSamplesAndDetectionsInOrder() {
        var buffer = HeadphoneMotionRawCaptureBuffer()

        buffer.recordSample(makeSample(timestamp: 0))
        buffer.recordSample(makeSample(timestamp: 0.02))
        buffer.recordDetection(makeDetection(stepCount: 1, timestamp: 0.02))

        let snapshot = buffer.snapshot()
        #expect(snapshot.samples.count == 2)
        #expect(snapshot.detections.count == 1)
        #expect(snapshot.samples.map(\.timestamp) == [0, 0.02])
        #expect(snapshot.didTruncateSamples == false)
        #expect(snapshot.didTruncateDetections == false)
    }

    @Test
    func truncatesSamplesAtTheConfiguredCapAndFlagsIt() {
        var buffer = HeadphoneMotionRawCaptureBuffer()
        let overCap = HeadphoneMotionRawCaptureLimits.maximumSampleCount + 5

        for index in 0..<overCap {
            buffer.recordSample(makeSample(timestamp: TimeInterval(index) * 0.02))
        }

        let snapshot = buffer.snapshot()
        #expect(snapshot.samples.count == HeadphoneMotionRawCaptureLimits.maximumSampleCount)
        #expect(snapshot.didTruncateSamples)
        // The buffer keeps the climb's start, not an arbitrary window - that is what "replay
        // the algorithm's behavior" needs most from a truncated capture.
        #expect(snapshot.samples.first?.timestamp == 0)
    }

    @Test
    func truncatesDetectionsAtTheConfiguredCapAndFlagsIt() {
        var buffer = HeadphoneMotionRawCaptureBuffer()
        let overCap = HeadphoneMotionRawCaptureLimits.maximumDetectionCount + 3

        for index in 0..<overCap {
            buffer.recordDetection(makeDetection(stepCount: index + 1, timestamp: TimeInterval(index) * 0.3))
        }

        let snapshot = buffer.snapshot()
        #expect(snapshot.detections.count == HeadphoneMotionRawCaptureLimits.maximumDetectionCount)
        #expect(snapshot.didTruncateDetections)
    }

    @Test
    func resetClearsBufferedSamplesDetectionsAndTruncationFlags() {
        var buffer = HeadphoneMotionRawCaptureBuffer()
        for index in 0..<(HeadphoneMotionRawCaptureLimits.maximumSampleCount + 1) {
            buffer.recordSample(makeSample(timestamp: TimeInterval(index)))
        }
        #expect(buffer.snapshot().didTruncateSamples)

        buffer.reset()

        let snapshot = buffer.snapshot()
        #expect(snapshot.samples.isEmpty)
        #expect(snapshot.detections.isEmpty)
        #expect(snapshot.didTruncateSamples == false)
        #expect(snapshot.didTruncateDetections == false)
    }

    @Test
    func rawCaptureSampleQuantizesTimestampAndVectors() {
        let sample = HeadphoneMotionSample(
            timestamp: 183_456.123_456_789,
            userAcceleration: HeadphoneMotionVector(x: 0.012_345_678, y: -0.987_654_321, z: 0.5),
            rotationRate: HeadphoneMotionVector(x: 1.234_567_89, y: 0, z: -0.000_04),
            gravity: HeadphoneMotionVector(x: 0, y: 0.999_999_9, z: 0)
        )

        let record = HeadphoneMotionRawCaptureSample(sample: sample)

        #expect(record.timestamp == 183_456.123)
        #expect(record.userAcceleration == HeadphoneMotionVector(x: 0.0123, y: -0.9877, z: 0.5))
        #expect(record.rotationRate == HeadphoneMotionVector(x: 1.2346, y: 0, z: -0.0))
        #expect(record.gravity == HeadphoneMotionVector(x: 0, y: 1, z: 0))
    }

    @Test
    func quantizedSamplesStillReplayTheDetectorsVerticalProjection() {
        let sample = HeadphoneMotionSample(
            timestamp: 1.5,
            userAcceleration: HeadphoneMotionVector(x: 0.2, y: 0.4, z: 0.6),
            gravity: HeadphoneMotionVector(x: 0, y: 1, z: 0)
        )

        let record = HeadphoneMotionRawCaptureSample(sample: sample)
        let replayed = HeadphoneMotionStepDetector.verticalAcceleration(from: HeadphoneMotionSample(
            timestamp: record.timestamp,
            userAcceleration: record.userAcceleration,
            rotationRate: record.rotationRate,
            gravity: record.gravity
        ))

        #expect(replayed == HeadphoneMotionStepDetector.verticalAcceleration(from: sample))
    }

    @Test
    func fullCapCaptureOfNoisyMotionFitsWellUnderTheUploadCap() throws {
        var generator = SplitMix64(seed: 0x5EED)
        func noise(_ scale: Double) -> Double {
            (0..<6).reduce(0) { sum, _ in sum + Double.random(in: -1...1, using: &generator) } / 2 * scale
        }

        var buffer = HeadphoneMotionRawCaptureBuffer()
        var timestamp: TimeInterval = 183_456.123_456_789
        for index in 0..<HeadphoneMotionRawCaptureLimits.maximumSampleCount {
            timestamp += 0.02 + noise(0.0002)
            let phase = Double(index) * 0.02 * 2 * .pi * 1.4
            buffer.recordSample(HeadphoneMotionSample(
                timestamp: timestamp,
                userAcceleration: HeadphoneMotionVector(x: noise(0.05), y: noise(0.05), z: 0.25 * sin(phase) + noise(0.08)),
                rotationRate: HeadphoneMotionVector(x: noise(0.3), y: noise(0.3), z: noise(0.3)),
                gravity: HeadphoneMotionVector(x: 0.1 + noise(0.01), y: -0.2 + noise(0.01), z: -0.97 + noise(0.01))
            ))
        }
        let rawCapture = buffer.snapshot()
        let blob = StepAccuracyRawCaptureBlob(
            workoutId: "full-cap",
            metadata: HeadphoneMotionWorkoutMetadata(
                sampleCount: rawCapture.samples.count,
                climbId: nil,
                targetStepCount: nil,
                stopReason: .userStopped
            ),
            appSteps: 1_000,
            machineReportedSteps: 1_100,
            stepDiscrepancyAbs: 100,
            stepCorrections: [],
            rawCapture: rawCapture
        )

        let compressed = try GzipCodec.compress(try JSONEncoder().encode(blob))

        #expect(compressed.count * 2 < StepAccuracyRawCaptureStorageRepository.maximumCompressedBytes)
    }

    @Test
    func detectorThresholdsCurrentMirrorsTheDetectorsOwnConstants() {
        let thresholds = HeadphoneMotionDetectorThresholds.current

        #expect(thresholds.algorithmVersion == HeadphoneMotionStepDetector.algorithmVersion)
        #expect(thresholds.peakThreshold == HeadphoneMotionStepDetector.peakThreshold)
        #expect(thresholds.minimumTimeBetweenPeaksSeconds == HeadphoneMotionStepDetector.minimumTimeBetweenPeaks)
        #expect(thresholds.maximumPitchRotationRate == HeadphoneMotionStepDetector.maximumPitchRotationRate)
    }

    // MARK: - Blob serialization

    @Test
    func blobRoundTripsThroughGzipAndJSON() throws {
        var buffer = HeadphoneMotionRawCaptureBuffer()
        buffer.recordSample(makeSample(timestamp: 0))
        buffer.recordSample(makeSample(timestamp: 0.02))
        buffer.recordDetection(makeDetection(stepCount: 1, timestamp: 0.02))
        let rawCapture = buffer.snapshot()

        let route = HeadphoneAudioRouteSnapshot(
            rawPortName: "AirPods Pro",
            rawPortType: "BluetoothA2DPOutput",
            family: .airPodsPro,
            isHeadphoneClassOutputConnected: true
        )
        var metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 2,
            climbId: "empire-state-building",
            targetStepCount: 1_576,
            stopReason: .userStopped,
            headphoneRouteAtStart: route,
            headphoneRouteAtSave: route,
            isMotionCapableHeadphoneConnectedAtStart: true,
            isMotionCapableHeadphoneConnectedAtSave: true,
            didHeadphoneMotionDataFlow: true
        )
        metadata.applyMachineStepCalibration(machineReportedSteps: 630, appSteps: 500)

        let correction = HeadphoneMotionStepCorrection(
            elapsedSeconds: 120,
            detectedSteps: 180,
            correctedSteps: 200,
            deltaSteps: 20,
            trackingGapDurationSeconds: 0,
            totalUnavailableDurationSeconds: 0,
            interruptionCount: 0
        )
        let blob = StepAccuracyRawCaptureBlob(
            workoutId: "workout-1",
            metadata: metadata,
            appSteps: 500,
            machineReportedSteps: 630,
            stepDiscrepancyAbs: try #require(metadata.stepDiscrepancyAbs),
            stepCorrections: [correction],
            rawCapture: rawCapture
        )

        let encoded = try JSONEncoder().encode(blob)
        let gzipped = try GzipCodec.compress(encoded)
        let decompressed = try GzipCodec.decompress(gzipped)
        let decoded = try JSONDecoder().decode(StepAccuracyRawCaptureBlob.self, from: decompressed)

        #expect(decoded == blob)
        #expect(decoded.samples.count == 2)
        #expect(decoded.detections.count == 1)
        #expect(decoded.climbId == "empire-state-building")
        #expect(decoded.machineReportedSteps == 630)
        #expect(decoded.stepDiscrepancyAbs == 130)
        #expect(decoded.headphoneRouteAtStart?.family == .airPodsPro)
        #expect(decoded.detectorThresholds.algorithmVersion == HeadphoneMotionStepDetector.algorithmVersion)
        #expect(decoded.stepCorrections == [correction])
        #expect(decoded.sampleCount == 2)
        #expect(decoded.resumeBase == nil)
        #expect(decoded.isPartialCapture == false)
    }

    @Test
    func blobFromAResumedSessionIsMarkedPartialWithItsResumeBase() throws {
        var buffer = HeadphoneMotionRawCaptureBuffer()
        buffer.recordSample(makeSample(timestamp: 0))
        let resumeBase = HeadphoneMotionRawCaptureResumeBase(steps: 240, sampleCount: 9_000)
        let rawCapture = buffer.snapshot().resumed(from: resumeBase)

        let blob = StepAccuracyRawCaptureBlob(
            workoutId: "workout-3",
            metadata: HeadphoneMotionWorkoutMetadata(
                sampleCount: 9_001,
                climbId: nil,
                targetStepCount: nil,
                stopReason: .userStopped
            ),
            appSteps: 300,
            machineReportedSteps: 400,
            stepDiscrepancyAbs: 100,
            stepCorrections: [],
            rawCapture: rawCapture
        )
        let decoded = try JSONDecoder().decode(
            StepAccuracyRawCaptureBlob.self,
            from: try GzipCodec.decompress(try GzipCodec.compress(try JSONEncoder().encode(blob)))
        )

        #expect(decoded.resumeBase == resumeBase)
        #expect(decoded.sampleCount == 9_001)
        #expect(decoded.isPartialCapture)
    }

    @Test
    func blobCarriesTruncationFlagsThrough() throws {
        var buffer = HeadphoneMotionRawCaptureBuffer()
        for index in 0..<(HeadphoneMotionRawCaptureLimits.maximumSampleCount + 1) {
            buffer.recordSample(makeSample(timestamp: TimeInterval(index)))
        }
        let rawCapture = buffer.snapshot()

        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: rawCapture.samples.count,
            climbId: nil,
            targetStepCount: nil,
            stopReason: .userStopped
        )

        let blob = StepAccuracyRawCaptureBlob(
            workoutId: "workout-2",
            metadata: metadata,
            appSteps: 100,
            machineReportedSteps: 200,
            stepDiscrepancyAbs: 100,
            stepCorrections: [],
            rawCapture: rawCapture
        )

        #expect(blob.didTruncateSamples)
        #expect(blob.isPartialCapture)
        #expect(blob.samples.count == HeadphoneMotionRawCaptureLimits.maximumSampleCount)
    }
}

private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
