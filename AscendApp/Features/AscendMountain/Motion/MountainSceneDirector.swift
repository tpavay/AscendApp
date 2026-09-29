import Foundation
import simd

/// One chunk slot as the renderer should draw it this frame.
struct MountainChunkSlotFrame: Equatable, Sendable {
    let slot: Int
    let chunkIndex: Int
    let kind: MountainChunkKind
    /// Where the piece sits on the course, for building the mountainside around it.
    let placement: MountainChunkPlacement
    /// The piece's entry, relative to the render origin.
    let renderPosition: SIMD3<Float>
    let heading: Float
}

/// Everything the renderer needs for one frame, already in render space.
///
/// Render space is course space shifted by `renderOrigin`, which is re-anchored near the
/// athlete as they climb, so every coordinate handed to RealityKit stays within tens of metres
/// of zero whether the climb is at step 100 or step 1,000,000 (spec 10).
/// A marker standing on the course this frame, placed in render space.
struct MountainMarkerFrame: Equatable, Sendable {
    let marker: MountainMarker
    let renderPosition: SIMD3<Float>
    let heading: Float
}

struct MountainSceneFrame: Equatable, Sendable {
    let logicalSteps: Int
    let visualSteps: Double
    let followerVelocity: Double
    let progress: MountainCourseProgress
    let cadenceStepsPerMinute: Double
    let pacing: MountainAnimationPacing
    let renderOrigin: SIMD3<Double>
    let slots: [MountainChunkSlotFrame]
    /// Slots whose piece changed this frame and need their geometry swapped.
    let reassignedSlots: Set<Int>
    let athlete: MountainAthleteKinematics
    let athleteRenderHipCentre: SIMD3<Float>
    let athleteRenderLeftFoot: SIMD3<Float>
    let athleteRenderRightFoot: SIMD3<Float>
    let athleteHeading: Float
    let cameraPosition: SIMD3<Float>
    let cameraTarget: SIMD3<Float>
    let recycleCount: Int
    let idleSlotCount: Int
    let markers: [MountainMarkerFrame]
    /// Ghosts close enough to stand on the stairs in view.
    let ghosts: [MountainGhostFrame]

    func renderPoint(_ coursePoint: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3<Float>(coursePoint - renderOrigin)
    }
}

/// The frame-by-frame brain of Ascend Mountain, with no RealityKit in it.
///
/// It reads the workout's authoritative step count and decides where the athlete, the camera
/// and each pooled chunk go. Everything is rebuilt from `(step count, seed)`: a scene that is
/// torn down and recreated starts its follower at the live count, so the athlete reappears on
/// the stair they are on instead of re-climbing from the bottom.
struct MountainSceneDirector: Sendable {
    struct CameraTuning: Equatable, Sendable {
        /// Camera offset behind and above the athlete, in the athlete's frame.
        var offset = SIMD3<Double>(0, 3.0, 5.6)
        /// How many steps ahead of the athlete the camera looks, so upcoming stairs stay in view.
        var lookAheadSteps = 8.0
        var lookHeight = 0.0
        /// How far toward the look-ahead point, rather than the athlete, the camera aims.
        var lookAheadWeight = 0.7
        var positionSmoothingSeconds = 0.22
        var targetSmoothingSeconds = 0.3
        var headingSmoothingSeconds = 0.55
        /// A camera further than this from where it should be has been through a jump; snap it.
        var snapDistance = 20.0

        static let standard = CameraTuning()
    }

    /// The render origin is re-anchored once the athlete is this far from it.
    static let reanchorDistance = 48.0

    private(set) var course: MountainCourse
    private(set) var pool: MountainChunkPool
    private let world: MountainWorld?
    private(set) var cadence = MountainCadenceEstimator()
    private(set) var follower: MountainStepFollower?
    private let cameraTuning: CameraTuning
    private var renderOrigin: SIMD3<Double>?
    private var cameraPosition: SIMD3<Double>?
    private var cameraTarget: SIMD3<Double>?
    private var cameraHeading: Double?
    private var smoothedIntensity = 0.0
    private var smoothedMovement = 0.0
    /// Set when rendering stopped for a while (the app was in the background, the view was torn
    /// down); the next frame places everything from the authoritative count instead of climbing
    /// through the steps the climber took off screen.
    private var needsResynchronization = false

    init(seed: UInt64, world: MountainWorld? = nil, cameraTuning: CameraTuning = .standard) {
        self.course = MountainCourse(seed: seed)
        self.pool = MountainChunkPool()
        self.world = world
        self.cameraTuning = cameraTuning
    }

    /// The mountain is a renderer of the workout, never a record of it: after rendering pauses,
    /// the next frame shows exactly where the authoritative count says, with no replay of the
    /// steps taken while nobody was watching.
    mutating func resynchronize() {
        needsResynchronization = true
    }

    /// How far from the climber a ghost is still drawn. Beyond this it is only a number in the
    /// HUD, which also keeps the course from regenerating far-off pieces every frame.
    static let ghostDrawRange: ClosedRange<Double> = -60...200

    /// Where across the stairs a ghost climbs, metres right of centre: fixed by its id, so a
    /// start line full of climbers spreads into a pack instead of queuing in single file. The
    /// climber themselves keeps the middle.
    static func lane(for id: String) -> Double {
        let hash = id.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1.value)) &* 1_099_511_628_211 }
        let unit = Double(hash % 10_000) / 9_999
        return (unit * 2 - 1) * 0.5
    }

    mutating func advance(logicalSteps: Int, time: Double, deltaTime: Double, ghosts: [MountainGhostSample] = []) -> MountainSceneFrame {
        let steps = max(logicalSteps, 0)
        let dt = deltaTime.isFinite ? min(max(deltaTime, 0), 0.25) : 0

        if needsResynchronization {
            needsResynchronization = false
            follower = MountainStepFollower(visualSteps: Double(steps))
            cadence = MountainCadenceEstimator()
            cameraPosition = nil
            cameraTarget = nil
            cameraHeading = nil
            smoothedMovement = 0
        }

        cadence.observe(stepCount: steps, at: time)
        let stepsPerSecond = cadence.stepsPerSecond(at: time)

        var follower = self.follower ?? MountainStepFollower(visualSteps: Double(steps))
        follower.advance(toward: Double(steps), cadence: stepsPerSecond, deltaTime: dt)
        self.follower = follower
        let visualSteps = follower.visualSteps

        let movingTarget = follower.velocity > 0.05 ? 1.0 : 0.0
        smoothedMovement = Self.smooth(smoothedMovement, toward: movingTarget, seconds: 0.25, deltaTime: dt)
        let pacing = MountainAnimationPacing(stepsPerMinute: stepsPerSecond * 60)
        smoothedIntensity = Self.smooth(smoothedIntensity, toward: pacing.intensity, seconds: 0.4, deltaTime: dt)

        let progress = course.progress(atSteps: visualSteps)
        var course = self.course
        let athlete = MountainAthleteKinematics(
            visualSteps: visualSteps,
            intensity: smoothedIntensity,
            movement: smoothedMovement,
            time: time,
            pose: { course.progress(atSteps: $0).pose }
        )
        self.course = course

        let origin = resolveRenderOrigin(athletePosition: progress.pose.position, currentChunk: progress.chunkIndex)
        let assignments = pool.update(currentChunk: progress.chunkIndex)
        let slots = pool.slotChunkIndices.enumerated().compactMap { slot, chunkIndex -> MountainChunkSlotFrame? in
            guard let chunkIndex else { return nil }
            let placement = self.course.placement(at: chunkIndex)
            return MountainChunkSlotFrame(
                slot: slot,
                chunkIndex: chunkIndex,
                kind: placement.kind,
                placement: placement,
                renderPosition: SIMD3<Float>(placement.entry.position - origin),
                heading: Float(placement.entry.heading)
            )
        }

        let lookAhead = self.course.progress(atSteps: visualSteps + cameraTuning.lookAheadSteps).pose.position
        let camera = updateCamera(athletePose: progress.pose, lookAhead: lookAhead, deltaTime: dt)
        let markers = (world?.markers(near: visualSteps) ?? []).map { marker -> MountainMarkerFrame in
            let pose = self.course.progress(atSteps: Double(self.course.markerStep(for: marker.step))).pose
            return MountainMarkerFrame(marker: marker, renderPosition: SIMD3<Float>(pose.position - origin), heading: Float(pose.heading))
        }

        let ghostFrames = ghosts.compactMap { ghost -> MountainGhostFrame? in
            let lead = ghost.steps - visualSteps
            guard Self.ghostDrawRange.contains(lead) else { return nil }
            let pacing = MountainAnimationPacing(stepsPerMinute: ghost.stepsPerMinute)
            let lane = Self.lane(for: ghost.id)
            var course = self.course
            let kinematics = MountainAthleteKinematics(
                visualSteps: max(ghost.steps, 0),
                intensity: pacing.intensity,
                movement: ghost.stepsPerMinute > 1 ? 1 : 0,
                time: time,
                pose: { steps in
                    let pose = course.progress(atSteps: steps).pose
                    return MountainPose(position: pose.position + pose.right * lane, heading: pose.heading)
                }
            )
            self.course = course
            return MountainGhostFrame(id: ghost.id, kind: ghost.kind, label: ghost.label, kinematics: kinematics, lead: lead)
        }

        return MountainSceneFrame(
            logicalSteps: steps,
            visualSteps: visualSteps,
            followerVelocity: follower.velocity,
            progress: progress,
            cadenceStepsPerMinute: stepsPerSecond * 60,
            pacing: pacing,
            renderOrigin: origin,
            slots: slots,
            reassignedSlots: Set(assignments.map(\.slot)),
            athlete: athlete,
            athleteRenderHipCentre: SIMD3<Float>(athlete.hipCentre - origin),
            athleteRenderLeftFoot: SIMD3<Float>(athlete.leftFoot - origin),
            athleteRenderRightFoot: SIMD3<Float>(athlete.rightFoot - origin),
            athleteHeading: Float(athlete.bodyPose.heading),
            cameraPosition: SIMD3<Float>(camera.position - origin),
            cameraTarget: SIMD3<Float>(camera.target - origin),
            recycleCount: pool.recycleCount,
            idleSlotCount: pool.idleSlotCount,
            markers: markers,
            ghosts: ghostFrames
        )
    }

    /// Keeps the render origin at the current piece's entry until the athlete has moved far
    /// enough from it to matter, so re-anchoring - which moves every entity at once - is rare.
    private mutating func resolveRenderOrigin(athletePosition: SIMD3<Double>, currentChunk: Int) -> SIMD3<Double> {
        if let renderOrigin, simd_length(athletePosition - renderOrigin) < Self.reanchorDistance {
            return renderOrigin
        }
        let origin = course.placement(at: currentChunk).entry.position
        renderOrigin = origin
        return origin
    }

    private mutating func updateCamera(
        athletePose: MountainPose,
        lookAhead: SIMD3<Double>,
        deltaTime: Double
    ) -> (position: SIMD3<Double>, target: SIMD3<Double>) {
        let heading = Self.smoothAngle(
            cameraHeading ?? athletePose.heading,
            toward: athletePose.heading,
            seconds: cameraTuning.headingSmoothingSeconds,
            deltaTime: deltaTime
        )
        cameraHeading = heading

        let framing = MountainPose(position: athletePose.position, heading: heading)
        let desiredPosition = framing.composed(
            with: MountainPose(position: cameraTuning.offset, heading: 0)
        ).position
        // Aim between the athlete and the stairs ahead: straight up a flight that is the stairs,
        // and round a turn the athlete stays in frame instead of the view swinging off them.
        let aim = athletePose.position + (lookAhead - athletePose.position) * cameraTuning.lookAheadWeight
        let desiredTarget = aim + SIMD3(0, cameraTuning.lookHeight, 0)

        let position: SIMD3<Double>
        let target: SIMD3<Double>
        if let cameraPosition,
           let cameraTarget,
           simd_length(cameraPosition - desiredPosition) < cameraTuning.snapDistance {
            position = Self.smooth(cameraPosition, toward: desiredPosition, seconds: cameraTuning.positionSmoothingSeconds, deltaTime: deltaTime)
            target = Self.smooth(cameraTarget, toward: desiredTarget, seconds: cameraTuning.targetSmoothingSeconds, deltaTime: deltaTime)
        } else {
            position = desiredPosition
            target = desiredTarget
            cameraHeading = athletePose.heading
        }
        cameraPosition = position
        cameraTarget = target
        return (position, target)
    }

    static func smooth(_ value: Double, toward target: Double, seconds: Double, deltaTime: Double) -> Double {
        guard seconds > 0 else { return target }
        return value + (target - value) * (1 - exp(-deltaTime / seconds))
    }

    static func smooth(_ value: SIMD3<Double>, toward target: SIMD3<Double>, seconds: Double, deltaTime: Double) -> SIMD3<Double> {
        guard seconds > 0 else { return target }
        return value + (target - value) * (1 - exp(-deltaTime / seconds))
    }

    static func smoothAngle(_ value: Double, toward target: Double, seconds: Double, deltaTime: Double) -> Double {
        var delta = (target - value).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        guard seconds > 0 else { return value + delta }
        return value + delta * (1 - exp(-deltaTime / seconds))
    }
}
