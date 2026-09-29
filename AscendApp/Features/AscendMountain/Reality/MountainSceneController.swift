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
        var athlete: MountainAthleteRig
        /// The look the climber's own rig was built with.
        var athleteLook: AthleteLook
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
    private let athleteLook: @MainActor () -> AthleteLook
    private let athletes: MountainAthleteLibrary
    private let journeySource: @MainActor () -> Int
    private let cameraTuning: MountainSceneDirector.CameraTuning
    private var ghostRigs: [String: MountainAthleteRig] = [:]
    /// What each ghost's rig was built as. Its tag, look and body are baked into it, so a change
    /// to any of them - a rival's own look arriving after their stand-in - means a new rig.
    private var ghostRigBuilds: [String: GhostRigBuild] = [:]

    private struct GhostRigBuild: Equatable {
        let label: String
        let style: MountainAthleteRig.Style
        let figure: MountainAthleteFigure.Key
    }
    private var director: MountainSceneDirector
    private var scene: Scene?
    private var updateSubscription: EventSubscription?
    /// Which placement each slot's mountainside was baked for, so a slot is rebuilt only when
    /// it is handed a new piece.
    private var decorBuiltFor: [Int: Int] = [:]
    /// The same course the director climbs, for the pieces either side of one being given its
    /// mountainside: a tree may stand beside a neighbouring flight the camera follows.
    private var decorCourse: MountainCourse
    /// The pieces whose stairs a piece's ground and trees keep clear of: any within this many
    /// either side whose entry is near, because the course switches back and a mountainside can
    /// fall onto a flight several pieces below it. Wide enough that two pieces sharing an edge
    /// always weigh the same stairs, so the ground meets without a seam.
    nonisolated static let decorNeighbours = 24
    nonisolated static let decorNeighbourMetres = 70.0

    /// The pieces near `piece` on `course`, for `MountainTerrainPatch`'s `nearby`.
    nonisolated static func decorNeighbours(of piece: MountainChunkPlacement, on course: inout MountainCourse) -> [MountainChunkPlacement] {
        (piece.index - decorNeighbours...piece.index + decorNeighbours)
            .filter { $0 != piece.index }
            .map { course.placement(at: $0) }
            .filter {
                simd_distance(SIMD2($0.entry.position.x, $0.entry.position.z), SIMD2(piece.entry.position.x, piece.entry.position.z))
                    < decorNeighbourMetres
            }
    }

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
    ///   - athleteLook: how the climber's own athlete looks, read every frame so a look that
    ///     arrives or changes during the climb is worn at once.
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
        athleteLook: @escaping @MainActor () -> AthleteLook = { .starting(for: nil) },
        athletes: MountainAthleteLibrary = .shared,
        journeySource: @escaping @MainActor () -> Int = { 0 },
        cameraTuning: MountainSceneDirector.CameraTuning = .standard
    ) {
        self.seed = seed
        self.cameraTuning = cameraTuning
        self.worldSource = worldSource
        self.ghostSource = ghostSource
        self.markerSource = markerSource
        self.elapsedSource = elapsedSource
        self.athleteLook = athleteLook
        self.athletes = athletes
        self.journeySource = journeySource
        self.stepSource = stepSource
        self.debugState = debugState
        self.director = MountainSceneDirector(seed: seed)
        self.decorCourse = MountainCourse(seed: seed)
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
        let look = athleteLook()
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
            athlete = try MountainAthleteRig(figure: try await athletes.figure(for: look), style: .athlete(look))
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
            athleteLook: look,
            camera: camera,
            sun: sun,
            far: far
        )
    }

    private func step(deltaTime: TimeInterval) {
        guard scene != nil else { return }
        rebuildAthleteIfLookChanged()
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
        let ghosts = ghostSource()
        director.liftsAtGates = !UIAccessibility.isReduceMotionEnabled
        let frame = director.advance(
            logicalSteps: logicalSteps,
            time: clock,
            deltaTime: deltaTime,
            ghosts: ghosts.map { MountainGhostSample(ghost: $0, elapsed: elapsed) },
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
        placeGhosts(frame, looks: Dictionary(ghosts.map { ($0.id, $0.look) }, uniquingKeysWith: { first, _ in first }), in: scene)
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

    /// The climber's own look can arrive or change mid-climb (read from their account after the
    /// scene was built, or saved on another phone); their rig is rebuilt as soon as the new
    /// figure is loaded, and until then they keep the look they have.
    private func rebuildAthleteIfLookChanged() {
        guard var scene else { return }
        let look = athleteLook()
        guard look != scene.athleteLook,
              let figure = athletes.readyFigure(for: look),
              let rebuilt = try? MountainAthleteRig(figure: figure, style: .athlete(look)) else { return }
        scene.athlete.root.removeFromParent()
        scene.root.addChild(rebuilt.root)
        scene.athlete = rebuilt
        scene.athleteLook = look
        self.scene = scene
    }

    /// Stands each ghost in view on its stair, building its rig the first time it comes near and
    /// once its body has loaded. A rival wears their own look, or a stand-in until it is read;
    /// the climber's best is their own figure in gold; a pacer is the starting athlete in blue.
    private func placeGhosts(_ frame: MountainSceneFrame, looks: [String: AthleteLook?], in scene: Scene) {
        let visible = Set(frame.ghosts.map(\.id))
        for (id, rig) in ghostRigs where !visible.contains(id) {
            rig.root.isEnabled = false
        }
        for ghost in frame.ghosts {
            let look: AthleteLook
            let style: MountainAthleteRig.Style
            switch ghost.kind {
            case .personalBest:
                look = scene.athleteLook
                style = .ghost(MountainColor(red: 0.83, green: 0.69, blue: 0.22))
            case .pacer:
                look = .starting(for: nil)
                style = .ghost(MountainColor(red: 0.75, green: 0.9, blue: 1))
            case .rival:
                look = (looks[ghost.id] ?? nil) ?? .standIn(for: ghost.id)
                style = .athlete(look)
            }
            let build = GhostRigBuild(label: ghost.label, style: style, figure: MountainAthleteFigure.Key(look))

            let rig: MountainAthleteRig
            if let existing = ghostRigs[ghost.id], ghostRigBuilds[ghost.id] == build {
                rig = existing
            } else if let figure = athletes.readyFigure(for: look),
                      let made = try? MountainAthleteRig(figure: figure, style: style, label: ghost.label) {
                ghostRigs[ghost.id]?.root.removeFromParent()
                scene.root.addChild(made.root)
                ghostRigs[ghost.id] = made
                ghostRigBuilds[ghost.id] = build
                rig = made
            } else if let existing = ghostRigs[ghost.id] {
                // The new body is still loading; keep drawing the old one meanwhile.
                rig = existing
            } else {
                continue
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
        let nearby = Self.decorNeighbours(of: slot.placement, on: &decorCourse)
        let patch = MountainTerrainPatch(placement: slot.placement, regions: environment.world.regions, nearby: nearby)
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
