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
    func rawCaptureSampleStoresTheDetectorsVerticalAccelerationProjection() {
        let sample = HeadphoneMotionSample(
            timestamp: 1.5,
            userAcceleration: HeadphoneMotionVector(x: 0.2, y: 0.4, z: 0.6),
            gravity: HeadphoneMotionVector(x: 0, y: 1, z: 0)
        )

        let record = HeadphoneMotionRawCaptureSample(sample: sample)

        #expect(record.verticalAcceleration == HeadphoneMotionStepDetector.verticalAcceleration(from: sample))
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

        let blob = StepAccuracyRawCaptureBlob(
            workoutId: "workout-1",
            metadata: metadata,
            appSteps: 500,
            machineReportedSteps: 630,
            stepDiscrepancyAbs: try #require(metadata.stepDiscrepancyAbs),
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
            rawCapture: rawCapture
        )

        #expect(blob.didTruncateSamples)
        #expect(blob.samples.count == HeadphoneMotionRawCaptureLimits.maximumSampleCount)
    }
}
