import Foundation
import SwiftData
import Testing

@testable import AscendApp

/// End-to-end wiring evidence: a saved climb's buffered raw motion capture reaches
/// `StepAccuracyRawCaptureStorageRepository` only on the retention trigger, and is never uploaded
/// otherwise. `StepAccuracyRawCaptureRetentionPolicyTests` covers the trigger logic in isolation;
/// this proves `LiveClimbSessionViewModel` actually calls through it.
@MainActor
struct LiveClimbSessionStepAccuracyRawCaptureTests {
    @Test("A discrepancy at the 30-step threshold, fully connected, uploads the raw capture")
    func uploadsOnQualifyingDiscrepancy() async throws {
        let repository = FakeStepAccuracyRawCaptureStorageRepository()
        let (viewModel, context) = try await Self.recordAndSaveAClimb(
            appSteps: 500,
            rawCaptureRepository: repository
        )

        viewModel.submitStepAccuracyCalibration(machineReportedSteps: 530, modelContext: context)
        await viewModel.rawCaptureUploadTask?.value

        let upload = try #require(await repository.uploads.first)
        #expect(upload.userId == "test-user-id")
        #expect(upload.blob.appSteps == 500)
        #expect(upload.blob.machineReportedSteps == 530)
        #expect(upload.blob.stepDiscrepancyAbs == 30)
        #expect(upload.blob.samples.count == 3)
        #expect(upload.blob.detections.count == 1)
        #expect(upload.blob.stepCorrections == [Self.stepCorrection])
        #expect(upload.blob.sampleCount == 3)
        #expect(upload.blob.isPartialCapture == false)
    }

    @Test("A session recovered after an app kill uploads a capture marked partial, with its resume base")
    func resumedSessionUploadIsMarkedPartial() async throws {
        let repository = FakeStepAccuracyRawCaptureStorageRepository()
        let resumeBase = HeadphoneMotionRawCaptureResumeBase(steps: 200, sampleCount: 7_500)
        let (viewModel, context) = try await Self.recordAndSaveAClimb(
            appSteps: 500,
            rawCaptureRepository: repository,
            resumeBase: resumeBase
        )

        viewModel.submitStepAccuracyCalibration(machineReportedSteps: 600, modelContext: context)
        await viewModel.rawCaptureUploadTask?.value

        let upload = try #require(await repository.uploads.first)
        #expect(upload.blob.resumeBase == resumeBase)
        #expect(upload.blob.isPartialCapture)
    }

    @Test("The kill switch off skips a qualifying upload, and it proceeds once the switch is on")
    func killSwitchGatesTheUpload() async throws {
        let blockedRepository = FakeStepAccuracyRawCaptureStorageRepository()
        let (blockedViewModel, blockedContext) = try await Self.recordAndSaveAClimb(
            appSteps: 500,
            rawCaptureRepository: blockedRepository,
            featureFlags: RemoteFeatureFlagStore(
                snapshot: .resolving(
                    remoteValues: [RemoteFeatureFlag.stepAccuracyRawCaptureUpload.key: false]
                )
            )
        )

        blockedViewModel.submitStepAccuracyCalibration(machineReportedSteps: 600, modelContext: blockedContext)

        #expect(blockedViewModel.rawCaptureUploadTask == nil)
        #expect(await blockedRepository.uploads.isEmpty)

        let allowedRepository = FakeStepAccuracyRawCaptureStorageRepository()
        let (allowedViewModel, allowedContext) = try await Self.recordAndSaveAClimb(
            appSteps: 500,
            rawCaptureRepository: allowedRepository,
            featureFlags: RemoteFeatureFlagStore(
                snapshot: .resolving(
                    remoteValues: [RemoteFeatureFlag.stepAccuracyRawCaptureUpload.key: true]
                )
            )
        )

        allowedViewModel.submitStepAccuracyCalibration(machineReportedSteps: 600, modelContext: allowedContext)
        await allowedViewModel.rawCaptureUploadTask?.value

        #expect(await allowedRepository.uploads.count == 1)
    }

    @Test("An overcount at or above thirty also uploads - the trigger is direction-agnostic")
    func uploadsOnQualifyingOvercount() async throws {
        let repository = FakeStepAccuracyRawCaptureStorageRepository()
        let (viewModel, context) = try await Self.recordAndSaveAClimb(
            appSteps: 500,
            rawCaptureRepository: repository
        )

        viewModel.submitStepAccuracyCalibration(machineReportedSteps: 470, modelContext: context)
        await viewModel.rawCaptureUploadTask?.value

        let upload = try #require(await repository.uploads.first)
        #expect(upload.blob.stepDiscrepancyAbs == 30)
    }

    @Test("A discrepancy under thirty steps never uploads")
    func discardsBelowThreshold() async throws {
        let repository = FakeStepAccuracyRawCaptureStorageRepository()
        let (viewModel, context) = try await Self.recordAndSaveAClimb(
            appSteps: 500,
            rawCaptureRepository: repository
        )

        viewModel.submitStepAccuracyCalibration(machineReportedSteps: 515, modelContext: context)

        // No Task is even spawned for a non-qualifying capture.
        #expect(viewModel.rawCaptureUploadTask == nil)
        #expect(await repository.uploads.isEmpty)
    }

    @Test("A headphone dropout during the climb never uploads, even with a large discrepancy")
    func discardsWhenNotConnectedThroughout() async throws {
        let repository = FakeStepAccuracyRawCaptureStorageRepository()
        let (viewModel, context) = try await Self.recordAndSaveAClimb(
            appSteps: 500,
            rawCaptureRepository: repository,
            trackingIntegrity: HeadphoneMotionTrackingIntegrity(
                currentUnavailableDuration: 0,
                totalUnavailableDuration: 8,
                longestUnavailableDuration: 8,
                interruptionCount: 1
            )
        )

        viewModel.submitStepAccuracyCalibration(machineReportedSteps: 600, modelContext: context)

        #expect(viewModel.rawCaptureUploadTask == nil)
        #expect(await repository.uploads.isEmpty)
    }

    @Test("Skipping calibration never uploads")
    func discardsWhenCalibrationIsSkipped() async throws {
        let repository = FakeStepAccuracyRawCaptureStorageRepository()
        let (viewModel, _) = try await Self.recordAndSaveAClimb(
            appSteps: 500,
            rawCaptureRepository: repository
        )

        viewModel.skipStepAccuracyCalibration()

        #expect(viewModel.rawCaptureUploadTask == nil)
        #expect(await repository.uploads.isEmpty)
    }

    // MARK: - Setup

    private static func recordAndSaveAClimb(
        appSteps: Int,
        rawCaptureRepository: FakeStepAccuracyRawCaptureStorageRepository,
        trackingIntegrity: HeadphoneMotionTrackingIntegrity = .verified,
        resumeBase: HeadphoneMotionRawCaptureResumeBase? = nil,
        featureFlags: RemoteFeatureFlagStore = RemoteFeatureFlagStore()
    ) async throws -> (LiveClimbSessionViewModel, ModelContext) {
        let climb = Self.climb
        let startedAt = Date().addingTimeInterval(-600)
        let motionSession = FakeHeadphoneMotionSession()

        var buffer = HeadphoneMotionRawCaptureBuffer()
        for index in 0..<3 {
            buffer.recordSample(HeadphoneMotionSample(
                timestamp: TimeInterval(index) * 0.02,
                userAcceleration: HeadphoneMotionVector(x: 0.1, y: 0.1, z: 0.1),
                gravity: HeadphoneMotionVector(x: 0, y: 0, z: 1)
            ))
        }
        buffer.recordDetection(HeadphoneMotionStepDetection(
            stepCount: 1,
            timestamp: 0.04,
            filteredVerticalAcceleration: 0.3
        ))

        motionSession.stopResult = HeadphoneMotionSessionResult(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            duration: 600,
            steps: appSteps,
            sampleCount: 3,
            stopReason: .targetReached,
            trackingIntegrity: trackingIntegrity,
            stepCorrections: [Self.stepCorrection],
            rawCapture: buffer.snapshot().resumed(from: resumeBase)
        )

        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let context = container.mainContext

        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [climb])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            rawCaptureRepository: rawCaptureRepository,
            currentUserId: { "test-user-id" },
            featureFlags: featureFlags
        )

        viewModel.start(modelContext: context)
        await viewModel.finishAndSave(modelContext: context, reason: .targetReached)

        return (viewModel, context)
    }

    private static let stepCorrection = HeadphoneMotionStepCorrection(
        elapsedSeconds: 90,
        detectedSteps: 140,
        correctedSteps: 150,
        deltaSteps: 10,
        trackingGapDurationSeconds: 0,
        totalUnavailableDurationSeconds: 0,
        interruptionCount: 0
    )

    private static let climb = Climb(
        id: "raw-capture-test-tower",
        name: "Test Tower",
        city: "Toronto",
        country: "Canada",
        continent: "North America",
        latitude: 43.6426,
        longitude: -79.3871,
        totalHeightMeters: 553,
        totalHeightFeet: 1_815,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 2_579,
        realStairCount: 2_579,
        calculatedFloors: 144,
        category: "tower",
        tier: .gold,
        tags: [],
        funFact: "Fact",
        sourceURL: "https://example.com",
        imageSetVersion: 1,
        releaseState: .available
    )
}

private actor FakeStepAccuracyRawCaptureStorageRepository: StepAccuracyRawCaptureStorageRepositoryProtocol {
    struct Upload: Equatable {
        let userId: String
        let workoutId: UUID
        let blob: StepAccuracyRawCaptureBlob
    }

    private(set) var uploads: [Upload] = []

    func uploadRawCapture(userId: String, workoutId: UUID, blob: StepAccuracyRawCaptureBlob) async throws {
        uploads.append(Upload(userId: userId, workoutId: workoutId, blob: blob))
    }
}
