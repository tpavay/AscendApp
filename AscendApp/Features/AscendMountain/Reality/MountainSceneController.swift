import Foundation
import RealityKit
import SwiftUI
import UIKit

/// Applies `MountainSceneDirector`'s frames to RealityKit entities.
///
/// It owns the entities - the pooled chunk slots with their stairs and mountainside, the athlete,
/// one camera, one sun, the far scenery - and nothing else: every decision is the director's,
/// and the only input is the workout's step count, read once per rendered frame. The workout
/// never waits on this and never reads from it, so the scene can be torn down and rebuilt at any
/// moment without touching the climb (spec 28).
///
/// Construction is deliberately cheap - SwiftUI may build and discard the owning view's initial
/// state on any parent update - and every entity is created on the first `install`.
@MainActor
final class MountainSceneController {
    private struct Scene {
        let resources: MountainSceneResources
        let environment: MountainEnvironmentResources
        let root: Entity
        let chunkSlots: [ModelEntity]
        let decorSlots: [ModelEntity]
        let athlete: MountainAthleteRig
        let athleteAsset: MountainAthleteAsset
        let camera: PerspectiveCamera
        let sun: DirectionalLight
        let far: MountainEnvironmentRig
    }

    private let stepSource: @MainActor () -> Int
    private let debugState: MountainDebugState?
    private let seed: UInt64
    private let worldSource: @Sendable () throws -> MountainWorld
    private let ghostSource: @MainActor () -> [MountainGhost]
    private let markerSource: @MainActor () -> [MountainMarker]
    private let elapsedSource: (@MainActor () -> TimeInterval)?
    private let journeySource: @MainActor () -> Int
    private let cameraTuning: MountainSceneDirector.CameraTuning
    private var ghostRigs: [String: MountainAthleteRig] = [:]
    /// The tag each ghost's rig was built with; a tag is baked into its rig, so a new one means
    /// a new rig.
    private var ghostRigLabels: [String: String] = [:]
    private var director: MountainSceneDirector
    private var scene: Scene?
    private var updateSubscription: EventSubscription?
    /// Which placement each slot's mountainside was baked for, so a slot is rebuilt only when
    /// it is handed a new piece.
    private var decorBuiltFor: [Int: Int] = [:]

    /// A gap this long between rendered frames means rendering was paused - the app went to the
    /// background, the phone locked - and the scene resynchronizes to the workout on return.
    static let resynchronizeAfterSeconds = 0.75
    /// Surround meshes built per frame at most, nearest pieces first, so a big jump in the count
    /// (a return from the background) never builds a whole window in one frame.
    static let decorBuildsPerFrame = 2

    private var clock: Double = 0
    private var lastFrameAt: TimeInterval?
    private var smoothedFrameSeconds = 1.0 / 60
    private var lastDebugPublishAt: Double = -1
    private var lastDecorBuildMilliseconds = 0.0

    /// - Parameters:
    ///   - worldSource: where the regions and markers come from; the bundled world file unless a
    ///     caller is previewing another.
    ///   - ghostSource: the other athletes on the stairs this frame - a best, a pacer, rivals.
    ///   - markerSource: this climb's own marks on the stairs, such as the line of the best.
    ///   - elapsedSource: the climb's own elapsed time, which places every ghost; the scene's
    ///     clock when a caller has no workout.
    ///   - journeySource: the steps the climber brought to this climb, where on the mountain its
    ///     first stair stands.
    init(
        seed: UInt64,
        stepSource: @escaping @MainActor () -> Int,
        debugState: MountainDebugState?,
        worldSource: @escaping @Sendable () throws -> MountainWorld = { try MountainWorld.bundled() },
        ghostSource: @escaping @MainActor () -> [MountainGhost] = { [] },
        markerSource: @escaping @MainActor () -> [MountainMarker] = { [] },
        elapsedSource: (@MainActor () -> TimeInterval)? = nil,
        journeySource: @escaping @MainActor () -> Int = { 0 },
        cameraTuning: MountainSceneDirector.CameraTuning = .standard
    ) {
        self.seed = seed
        self.cameraTuning = cameraTuning
        self.worldSource = worldSource
        self.ghostSource = ghostSource
        self.markerSource = markerSource
        self.elapsedSource = elapsedSource
        self.journeySource = journeySource
        self.stepSource = stepSource
        self.debugState = debugState
        self.director = MountainSceneDirector(seed: seed)
    }

    /// Called from `RealityView`'s make closure. Safe to call again with fresh content when
    /// SwiftUI rebuilds the view: the entities and the director's state carry over, so the
    /// athlete reappears where the step count says.
    func install(in content: inout RealityViewCameraContent) async {
        if scene == nil {
            await buildScene()
        }
        guard let scene else { return }

        content.camera = .virtual
        if let skybox = scene.environment.skybox {
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

    private func buildScene() async {
        let world: MountainWorld
        let resources: MountainSceneResources
        let far: MountainEnvironmentRig
        let environment: MountainEnvironmentResources
        let athlete: MountainAthleteRig
        let asset: MountainAthleteAsset
        do {
            world = try worldSource()
            var ground: [MountainTerrainBucket.Surface: MountainScannedMaterial] = [:]
            for surface in MountainTerrainBucket.Surface.allCases {
                ground[surface] = try? await MountainScannedMaterial.load("ascend-mountain-ground-\(surface)")
            }
            environment = MountainEnvironmentResources.make(
                world: world,
                stone: try? await MountainScannedMaterial.load("ascend-mountain-stone"),
                kerb: try? await MountainScannedMaterial.load("ascend-mountain-kerb"),
                ground: ground
            )
            resources = try MountainSceneResources.make()
            far = try MountainEnvironmentRig(resources: environment)
            asset = try await Task.detached(priority: .userInitiated) { try MountainAthleteAsset.bundled() }.value
            athlete = try MountainAthleteRig(asset: asset)
        } catch {
            AppDiagnosticsRecorder.shared.record(
                "ascend_mountain_scene_build_failed",
                level: .error,
                details: ["error": String(describing: error)]
            )
            return
        }
        guard scene == nil else { return }
        director = MountainSceneDirector(seed: seed, world: world, journeyStart: journeySource(), cameraTuning: cameraTuning)

        let root = Entity()
        root.addChild(far.root)
        var decorSlots: [ModelEntity] = []
        let chunkSlots = (0..<MountainChunkPool.Reach.lift.size).map { _ in
            let slot = ModelEntity()
            slot.isEnabled = false
            let decor = ModelEntity()
            slot.addChild(decor)
            decorSlots.append(decor)
            root.addChild(slot)
            return slot
        }

        root.addChild(athlete.root)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 60
        camera.camera.near = 0.05
        camera.camera.far = MountainEnvironmentRig.skyRadius * 1.8
        root.addChild(camera)
        far.attachVeil(to: camera)

        let sun = DirectionalLight()
        sun.light.intensity = 3_000
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 12, depthBias: 1.5)
        let toSun = SIMD3<Float>(MountainSkyImage.sunDirection)
        sun.look(at: .zero, from: toSun * 10, relativeTo: nil)
        root.addChild(sun)

        scene = Scene(
            resources: resources,
            environment: environment,
            root: root,
            chunkSlots: chunkSlots,
            decorSlots: decorSlots,
            athlete: athlete,
            athleteAsset: asset,
            camera: camera,
            sun: sun,
            far: far
        )
    }

    private func step(deltaTime: TimeInterval) {
        guard let scene else { return }

        let now = Date.timeIntervalSinceReferenceDate
        if let lastFrameAt, now - lastFrameAt > Self.resynchronizeAfterSeconds {
            director.resynchronize()
        }
        lastFrameAt = now

        clock += deltaTime
        if deltaTime > 0 {
            smoothedFrameSeconds += (deltaTime - smoothedFrameSeconds) * 0.1
        }

        let climbed = stepSource()
        // A journey total that lands while the climber is still on the start line moves the start
        // line; once they have stepped, the mountain under them never jumps.
        if climbed == 0 {
            director.rebase(journeyStart: journeySource())
        }
        let logicalSteps = climbed + (debugState?.visualStepOffset ?? 0)
        let elapsed = elapsedSource?() ?? clock
        director.liftsAtGates = !UIAccessibility.isReduceMotionEnabled
        let frame = director.advance(
            logicalSteps: logicalSteps,
            time: clock,
            deltaTime: deltaTime,
            ghosts: ghostSource().map { MountainGhostSample(ghost: $0, elapsed: elapsed) },
            extraMarkers: markerSource()
        )

        for slotFrame in frame.slots {
            let entity = scene.chunkSlots[slotFrame.slot]
            if frame.reassignedSlots.contains(slotFrame.slot) || entity.model == nil,
               let mesh = scene.resources.chunkMeshes[slotFrame.kind] {
                entity.model = ModelComponent(mesh: mesh, materials: scene.environment.stairMaterials)
            }
            entity.position = slotFrame.renderPosition
            entity.orientation = simd_quatf(angle: slotFrame.heading, axis: [0, 1, 0])
            entity.isEnabled = true
        }

        // Surrounds for newly assigned pieces, nearest first; a piece whose surround is still
        // waiting shows no stale ground from the piece it replaced.
        var builds = 0
        for slotFrame in frame.slots.sorted(by: { abs($0.chunkIndex - frame.progress.chunkIndex) < abs($1.chunkIndex - frame.progress.chunkIndex) })
            where decorBuiltFor[slotFrame.slot] != slotFrame.chunkIndex {
            let decor = scene.decorSlots[slotFrame.slot]
            guard builds < Self.decorBuildsPerFrame else {
                decor.isEnabled = false
                continue
            }
            buildDecor(for: slotFrame, into: decor, environment: scene.environment)
            decor.isEnabled = true
            builds += 1
        }

        scene.athlete.apply(frame.athlete, origin: frame.renderOrigin)
        placeGhosts(frame, in: scene)
        scene.athlete.showGroundRing(!frame.ghosts.isEmpty)
        scene.camera.look(at: frame.cameraTarget, from: frame.cameraPosition, relativeTo: nil)

        let regions = scene.environment.world.regions
        scene.sun.light.intensity = Float(regions.blended({ $0.sky.sunIntensity }, atSteps: frame.courseSteps) * 950)
        scene.far.update(
            camera: frame.cameraPosition,
            climberY: frame.athleteRenderHipCentre.y,
            steps: frame.courseSteps,
            altitude: frame.progress.virtualAltitude,
            deltaTime: deltaTime
        )
        scene.far.place(markers: frame.markers)
        scene.far.thinPassedGates(frame.markers, climberSteps: frame.courseSteps, lift: frame.cameraLift)

        publishDebugMetricsIfDue(frame)
    }

    /// Stands each ghost in view on its stair, building its rig the first time it comes near.
    private func placeGhosts(_ frame: MountainSceneFrame, in scene: Scene) {
        let visible = Set(frame.ghosts.map(\.id))
        for (id, rig) in ghostRigs where !visible.contains(id) {
            rig.root.isEnabled = false
        }
        for ghost in frame.ghosts {
            let rig: MountainAthleteRig
            if let existing = ghostRigs[ghost.id], ghostRigLabels[ghost.id] == ghost.label {
                rig = existing
            } else {
                ghostRigs[ghost.id]?.root.removeFromParent()
                let style: MountainAthleteRig.Style = switch ghost.kind {
                case .personalBest: .ghost(MountainColor(red: 0.83, green: 0.69, blue: 0.22))
                case .pacer: .ghost(MountainColor(red: 0.75, green: 0.9, blue: 1))
                case .rival: .athlete(.standIn(for: ghost.id))
                }
                guard let made = try? MountainAthleteRig(asset: scene.athleteAsset, style: style, label: ghost.label) else { continue }
                scene.root.addChild(made.root)
                ghostRigs[ghost.id] = made
                ghostRigLabels[ghost.id] = ghost.label
                rig = made
            }
            rig.apply(ghost.kinematics, origin: frame.renderOrigin)
            rig.showTag(opacity: Self.tagOpacity(lead: ghost.lead))
            rig.root.isEnabled = true
        }
    }

    /// A name is for the climbers around you. The stairs climb toward the camera, so the further
    /// ahead a ghost is the higher it stands in the frame, until its tag sits among the step count
    /// at the top; tags fade out from `tagFullLead` steps ahead and are gone by `tagHiddenLead`.
    static let tagFullLead = 5.0
    static let tagHiddenLead = 10.0

    static func tagOpacity(lead: Double) -> Float {
        Float(min(max((tagHiddenLead - lead) / (tagHiddenLead - tagFullLead), 0), 1))
    }

    /// Bakes the mountainside for the piece a slot has just been handed. A slot is handed a piece
    /// six pieces ahead of the climber, long before it can be seen.
    private func buildDecor(for slot: MountainChunkSlotFrame, into entity: ModelEntity, environment: MountainEnvironmentResources) {
        let started = Date()
        let patch = MountainTerrainPatch(placement: slot.placement, regions: environment.world.regions)
        let data = MountainDecorMeshData(patch: patch, layout: environment.layout)
        var descriptor = MeshDescriptor(name: "mountain-decor")
        descriptor.positions = MeshBuffers.Positions(data.positions)
        descriptor.normals = MeshBuffers.Normals(data.normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(data.uvs)
        descriptor.primitives = .triangles(data.indices)
        descriptor.materials = .perFace(data.faceMaterials)
        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            entity.model = ModelComponent(mesh: mesh, materials: environment.decorMaterials)
        }
        decorBuiltFor[slot.slot] = slot.chunkIndex
        lastDecorBuildMilliseconds = Date().timeIntervalSince(started) * 1_000
    }

    private func publishDebugMetricsIfDue(_ frame: MountainSceneFrame) {
        guard let debugState, clock - lastDebugPublishAt >= 0.25 else { return }
        lastDebugPublishAt = clock

        let currentKind = frame.slots.first { $0.chunkIndex == frame.progress.chunkIndex }?.kind
        let region = scene?.environment.world.regions.region(atSteps: frame.courseSteps)
        debugState.metrics = MountainDebugState.Metrics(
            framesPerSecond: smoothedFrameSeconds > 0 ? 1 / smoothedFrameSeconds : 0,
            logicalSteps: frame.logicalSteps,
            visualSteps: frame.visualSteps,
            mountainSteps: frame.courseSteps,
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
            biome: region.map { "\($0.id) (decor \(Int(lastDecorBuildMilliseconds.rounded())) ms)" } ?? "-",
            ghostCount: frame.ghosts.count,
            residentMemoryMegabytes: MountainDebugState.residentMemoryMegabytes()
        )
    }
}
