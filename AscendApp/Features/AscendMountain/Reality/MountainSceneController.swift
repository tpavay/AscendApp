import Foundation
import RealityKit
import SwiftUI

/// Applies `MountainSceneDirector`'s frames to RealityKit entities.
///
/// It owns the entities - six pooled chunk slots, the athlete, one camera, one light - and
/// nothing else: every decision is the director's, and the only input is the workout's step
/// count, read once per rendered frame. The workout never waits on this and never reads from it,
/// so the scene can be torn down and rebuilt at any moment without touching the climb (spec 28).
///
/// Construction is deliberately cheap - SwiftUI may build and discard the owning view's initial
/// state on any parent update - and every entity is created on the first `install`.
@MainActor
final class MountainSceneController {
    private struct Scene {
        let resources: MountainSceneResources
        let root: Entity
        let chunkSlots: [ModelEntity]
        let athlete: MountainAthleteRig
        let camera: PerspectiveCamera
    }

    private let stepSource: @MainActor () -> Int
    private let debugState: MountainDebugState?
    private var director: MountainSceneDirector
    private var scene: Scene?
    private var updateSubscription: EventSubscription?

    private var clock: Double = 0
    private var smoothedFrameSeconds = 1.0 / 60
    private var lastDebugPublishAt: Double = -1

    init(seed: UInt64, stepSource: @escaping @MainActor () -> Int, debugState: MountainDebugState?) {
        self.stepSource = stepSource
        self.debugState = debugState
        self.director = MountainSceneDirector(seed: seed)
    }

    /// Called from `RealityView`'s make closure. Safe to call again with fresh content when
    /// SwiftUI rebuilds the view: the entities and the director's state carry over, so the
    /// athlete reappears where the step count says.
    func install(in content: inout RealityViewCameraContent) {
        guard let scene = scene ?? buildScene() else { return }

        content.camera = .virtual
        if let skybox = scene.resources.skybox {
            content.environment = .skybox(skybox)
        }
        content.renderingEffects.motionBlur = .disabled
        content.renderingEffects.depthOfField = .disabled
        content.renderingEffects.cameraGrain = .disabled
        content.add(scene.root)

        updateSubscription?.cancel()
        updateSubscription = content.subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil) { [weak self] event in
            self?.step(deltaTime: event.deltaTime)
        }
        // Pose everything once before the first frame draws, so the scene never flashes empty.
        step(deltaTime: 0)
    }

    func stop() {
        updateSubscription?.cancel()
        updateSubscription = nil
    }

    private func buildScene() -> Scene? {
        let resources: MountainSceneResources
        do {
            resources = try MountainSceneResources.make()
        } catch {
            AppDiagnosticsRecorder.shared.record(
                "ascend_mountain_scene_build_failed",
                level: .error,
                details: ["error": error.localizedDescription]
            )
            return nil
        }

        let root = Entity()
        let chunkSlots = (0..<MountainChunkPool.windowSize).map { _ in
            let slot = ModelEntity()
            slot.isEnabled = false
            root.addChild(slot)
            return slot
        }

        let athlete = MountainAthleteRig()
        root.addChild(athlete.root)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 60
        camera.camera.near = 0.05
        camera.camera.far = 400
        root.addChild(camera)

        let sun = DirectionalLight()
        sun.light.intensity = 4_200
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 10, depthBias: 1.5)
        sun.look(at: [0, 0, 0], from: [2.5, 6, 1.5], relativeTo: nil)
        root.addChild(sun)

        let scene = Scene(resources: resources, root: root, chunkSlots: chunkSlots, athlete: athlete, camera: camera)
        self.scene = scene
        return scene
    }

    private func step(deltaTime: TimeInterval) {
        guard let scene else { return }

        clock += deltaTime
        if deltaTime > 0 {
            smoothedFrameSeconds += (deltaTime - smoothedFrameSeconds) * 0.1
        }

        let logicalSteps = stepSource() + (debugState?.visualStepOffset ?? 0)
        let frame = director.advance(logicalSteps: logicalSteps, time: clock, deltaTime: deltaTime)

        for slotFrame in frame.slots {
            let entity = scene.chunkSlots[slotFrame.slot]
            if frame.reassignedSlots.contains(slotFrame.slot) || entity.model == nil,
               let mesh = scene.resources.chunkMeshes[slotFrame.kind] {
                entity.model = ModelComponent(mesh: mesh, materials: scene.resources.chunkMaterials)
            }
            entity.position = slotFrame.renderPosition
            entity.orientation = simd_quatf(angle: slotFrame.heading, axis: [0, 1, 0])
            entity.isEnabled = true
        }

        scene.athlete.apply(frame.athlete, origin: frame.renderOrigin)
        scene.camera.look(at: frame.cameraTarget, from: frame.cameraPosition, relativeTo: nil)

        publishDebugMetricsIfDue(frame)
    }

    private func publishDebugMetricsIfDue(_ frame: MountainSceneFrame) {
        guard let debugState, clock - lastDebugPublishAt >= 0.25 else { return }
        lastDebugPublishAt = clock

        let currentKind = frame.slots.first { $0.chunkIndex == frame.progress.chunkIndex }?.kind
        debugState.metrics = MountainDebugState.Metrics(
            framesPerSecond: smoothedFrameSeconds > 0 ? 1 / smoothedFrameSeconds : 0,
            logicalSteps: frame.logicalSteps,
            visualSteps: frame.visualSteps,
            renderCadenceStepsPerMinute: frame.cadenceStepsPerMinute,
            animationPlaybackRate: frame.followerVelocity * 60 / MountainAnimationPacing.referenceStepsPerMinute,
            animationIntensity: frame.pacing.intensity,
            activeChunks: frame.slots.count,
            idleChunkSlots: frame.idleSlotCount,
            chunkRecycles: frame.recycleCount,
            chunkIndex: frame.progress.chunkIndex,
            chunkKind: currentKind?.rawValue ?? "-",
            virtualAltitudeMetres: frame.progress.virtualAltitude,
            renderOriginDistanceMetres: Double(simd_length(frame.athleteRenderHipCentre)),
            ghostCount: 0,
            residentMemoryMegabytes: MountainDebugState.residentMemoryMegabytes()
        )
    }
}
