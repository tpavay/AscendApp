import Foundation
import simd

/// Where the athlete's body should be this frame, in the athlete's model space (metres, +Y up,
/// facing +Z, the ground under the pelvis at the origin).
struct MountainAthletePoseTargets: Equatable, Sendable {
    /// The pelvis joint's position.
    var pelvis: SIMD3<Double>
    /// Where each foot joint should stand: on its tread, or on its way to the next one.
    var leftFoot: SIMD3<Double>
    var rightFoot: SIMD3<Double>
    /// Forward lean of the upper body, radians.
    var torsoLean: Double
    /// Left arm swing, radians forward; the right arm mirrors it.
    var leftArmSwing: Double
    /// Elbow bend, radians: a relaxed hang standing, a pumping arm climbing hard.
    var elbowBend: Double
    /// Hip-and-shoulder counter-twist with the stride, radians about +Y.
    var twist: Double
    /// How the arms hold a carried item, or nil when they swing free.
    var carry: MountainCarryHold? = nil
}

/// How a carried item sits on the athlete and where the hands hold it, in model space, from the
/// chest and right shoulder as this frame poses them. The poser reaches the hands to it and the
/// rig rests the item on it, so the two always agree.
struct MountainCarryHold: Equatable, Sendable {
    var carry: AthleteGear.Carry
    /// From the item's resting point up to its top, and half its width, in metres.
    var height: Double
    var halfWidth: Double

    /// Where the item rests: on top of the right shoulder, above the head on both hands, or out in
    /// front on the right palm.
    func seat(chest: SIMD3<Double>, chestTurn: simd_quatd, rightShoulder: SIMD3<Double>) -> SIMD3<Double> {
        switch carry {
        case .shoulder: rightShoulder + chestTurn.act(SIMD3(0.015, 0.075, -0.03))
        case .overhead: chest + chestTurn.act(SIMD3(0, 0.55, 0.04))
        case .tray: rightShoulder + chestTurn.act(SIMD3(-0.05, -0.1, 0.4))
        }
    }

    /// Where a wrist reaches, or nil for an arm left to swing. On the shoulder the right hand
    /// comes over the item's top from outside, the hand turned down over it; overhead both hands take
    /// the giant's sides from below.
    func wrist(side: Int, seat: SIMD3<Double>, chestTurn: simd_quatd) -> SIMD3<Double>? {
        let sign: Double = side == 0 ? 1 : -1
        switch (carry, side) {
        case (.shoulder, 1): return seat + chestTurn.act(SIMD3(-halfWidth * 0.62, height * 1.02, 0.03))
        case (.shoulder, _): return nil
        case (.overhead, _): return seat + chestTurn.act(SIMD3(sign * halfWidth * 0.9, height * 0.3, 0.02))
        case (.tray, 1): return seat + chestTurn.act(SIMD3(0, -0.035, -0.08))
        case (.tray, _): return nil
        }
    }

    /// Where a holding hand's fingers point: down over the shoulder item's crown, in against the
    /// giant's flank.
    func fingers(side: Int, seat: SIMD3<Double>, chestTurn: simd_quatd) -> SIMD3<Double>? {
        switch (carry, side) {
        case (.shoulder, 1): return seat + chestTurn.act(SIMD3(halfWidth * 0.1, height * 0.82, 0.02))
        case (.shoulder, _): return nil
        case (.overhead, _): return seat + chestTurn.act(SIMD3(0, height * 0.55, 0))
        case (.tray, 1): return seat + chestTurn.act(SIMD3(0, -0.035, 0.12))
        case (.tray, _): return nil
        }
    }

    /// Which way an elbow bends while it holds: out and down from the shoulder item, out to the
    /// sides under a giant.
    func elbowPole(side: Int, chestTurn: simd_quatd) -> SIMD3<Double> {
        let sign: Double = side == 0 ? 1 : -1
        switch carry {
        case .shoulder: return chestTurn.act(SIMD3(sign, -0.5, -0.15))
        case .overhead: return chestTurn.act(SIMD3(sign, -0.35, -0.25))
        case .tray: return chestTurn.act(SIMD3(sign * 0.3, -1, -0.4))
        }
    }
}

/// Poses the athlete's skeleton for a stair climb: frame-aligned pelvis and spine, two-bone leg
/// IK onto the tread targets with feet flat, arms swung from the shoulders.
///
/// Everything is solved in model space from the rest pose and returned as joint-local transforms
/// for RealityKit. It aims bones by direction rather than trusting the rig's rest angles, because
/// the authored rest pose is an idle stance (pelvis twisted, a foot turned out) rather than a
/// neutral one.
struct MountainAthletePoser: Sendable {
    struct LocalTransform: Equatable, Sendable {
        let translation: SIMD3<Float>
        let rotation: simd_quatf
    }

    private struct Chain: Sendable {
        let upper: Int
        let lower: Int
        let end: Int
        let upperLength: Double
        let lowerLength: Double
    }

    let jointCount: Int
    private let parents: [Int?]
    private let order: [Int]
    private let restLocalTranslation: [SIMD3<Double>]
    private let restLocalRotation: [simd_quatd]
    private let restGlobalPosition: [SIMD3<Double>]
    private let restGlobalRotation: [simd_quatd]

    private let body: Int
    private let spine: [Int]
    private let neck: Int
    private let head: Int
    private let legs: [Chain]
    private let arms: [Chain]
    /// For each wrist, the knuckle the hand bone runs to, so a holding hand can be turned onto
    /// what it holds. Nil on a rig without fingers, whose hands just follow the forearm.
    private let knuckles: [Int?]
    /// Rest-pose rotations that take each foot to point along +Z, flat.
    private let footCorrections: [simd_quatd]
    private let pelvisRestUp: SIMD3<Double>
    private let pelvisRestSide: SIMD3<Double>
    private let chestRestUp: SIMD3<Double>
    private let chestRestSide: SIMD3<Double>

    /// Height of the pelvis joint above the feet at rest.
    let restPelvisHeight: Double
    /// Height of a foot joint above the ground at rest.
    let restFootHeight: Double

    init?(joints: [(name: String, parent: Int?, translation: SIMD3<Double>, rotation: simd_quatd)], roles: MountainAthleteAsset.Roles) {
        func index(_ name: String) -> Int? { joints.firstIndex { $0.name == name } }
        let spine = roles.spine.compactMap(index)
        guard let body = index(roles.body), !spine.isEmpty, spine.count == roles.spine.count,
              let neck = index(roles.neck), let head = index(roles.head),
              roles.legs.count == 2, roles.arms.count == 2,
              roles.legs.allSatisfy({ $0.count == 3 }), roles.arms.allSatisfy({ $0.count == 3 }),
              let upperLegL = index(roles.legs[0][0]), let lowerLegL = index(roles.legs[0][1]), let footL = index(roles.legs[0][2]),
              let upperLegR = index(roles.legs[1][0]), let lowerLegR = index(roles.legs[1][1]), let footR = index(roles.legs[1][2]),
              let upperArmL = index(roles.arms[0][0]), let lowerArmL = index(roles.arms[0][1]), let wristL = index(roles.arms[0][2]),
              let upperArmR = index(roles.arms[1][0]), let lowerArmR = index(roles.arms[1][1]), let wristR = index(roles.arms[1][2]) else {
            return nil
        }
        let chest = spine[spine.count - 1]

        jointCount = joints.count
        parents = joints.map(\.parent)
        restLocalTranslation = joints.map(\.translation)
        restLocalRotation = joints.map { simd_normalize($0.rotation) }

        // Parents first, whatever order the rig lists them in.
        var order: [Int] = [], placed = Set<Int>()
        while order.count < joints.count {
            let before = order.count
            for (i, joint) in joints.enumerated() where !placed.contains(i) && (joint.parent.map(placed.contains) ?? true) {
                order.append(i)
                placed.insert(i)
            }
            if order.count == before { return nil }
        }
        self.order = order

        var positions = [SIMD3<Double>](repeating: .zero, count: joints.count)
        var rotations = [simd_quatd](repeating: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), count: joints.count)
        for i in order {
            if let parent = joints[i].parent {
                rotations[i] = simd_normalize(rotations[parent] * restLocalRotation[i])
                positions[i] = positions[parent] + rotations[parent].act(restLocalTranslation[i])
            } else {
                rotations[i] = restLocalRotation[i]
                positions[i] = restLocalTranslation[i]
            }
        }
        restGlobalPosition = positions
        restGlobalRotation = rotations

        self.body = body
        self.spine = spine
        self.neck = neck
        self.head = head
        legs = [(upperLegL, lowerLegL, footL), (upperLegR, lowerLegR, footR)].map { upper, lower, end in
            Chain(upper: upper, lower: lower, end: end,
                  upperLength: simd_distance(positions[upper], positions[lower]),
                  lowerLength: simd_distance(positions[lower], positions[end]))
        }
        knuckles = [wristL, wristR].map { wrist in
            let children = joints.indices.filter { joints[$0].parent == wrist }
            return children.first { joints[$0].name.hasPrefix("middle") } ?? children.first
        }
        arms = [(upperArmL, lowerArmL, wristL), (upperArmR, lowerArmR, wristR)].map { upper, lower, end in
            Chain(upper: upper, lower: lower, end: end,
                  upperLength: simd_distance(positions[upper], positions[lower]),
                  lowerLength: simd_distance(positions[lower], positions[end]))
        }

        pelvisRestUp = simd_normalize(positions[chest] - positions[body])
        pelvisRestSide = simd_normalize(positions[upperLegL] - positions[upperLegR])
        chestRestUp = simd_normalize(positions[neck] - positions[chest])
        chestRestSide = simd_normalize(positions[upperArmL] - positions[upperArmR])
        footCorrections = [footL, footR].map { foot in
            // A foot bone runs heel to toe along its local +Y.
            let along = rotations[foot].act(SIMD3(0, 1, 0))
            let flatAlong = simd_normalize(SIMD3(along.x, 0, along.z))
            return Self.align(fromUp: SIMD3(0, 1, 0), fromSide: simd_cross(SIMD3(0, 1, 0), flatAlong),
                              toUp: SIMD3(0, 1, 0), toSide: SIMD3(1, 0, 0))
        }
        restPelvisHeight = positions[body].y - (positions[footL].y + positions[footR].y) / 2
        restFootHeight = (positions[footL].y + positions[footR].y) / 2
    }

    init?(asset: MountainAthleteAsset) {
        self.init(joints: asset.joints.map { ($0.name, $0.parentIndex, $0.restTranslation, $0.restRotation) }, roles: asset.roles)
    }

    // MARK: - Solving

    func pose(_ targets: MountainAthletePoseTargets) -> [LocalTransform] {
        var position = [SIMD3<Double>](repeating: .zero, count: jointCount)
        var rotation = [simd_quatd](repeating: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), count: jointCount)
        var delta = [simd_quatd](repeating: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), count: jointCount)

        let lean = targets.torsoLean
        let pelvisCorrection = Self.align(
            fromUp: pelvisRestUp, fromSide: pelvisRestSide,
            toUp: Self.pitched(SIMD3(0, 1, 0), by: lean * 0.35),
            toSide: Self.yawed(SIMD3(1, 0, 0), by: targets.twist)
        )
        let chestCorrection = Self.align(
            fromUp: chestRestUp, fromSide: chestRestSide,
            toUp: Self.pitched(SIMD3(0, 1, 0), by: lean),
            toSide: Self.yawed(SIMD3(1, 0, 0), by: -targets.twist * 0.6)
        )
        // A head leans away from the item on its right shoulder, toward +X.
        let headRoll = targets.carry?.carry == .shoulder ? -0.14 : 0
        let headCorrection = Self.align(
            fromUp: chestRestUp, fromSide: chestRestSide,
            toUp: simd_quatd(angle: headRoll, axis: SIMD3(0, 0, 1)).act(Self.pitched(SIMD3(0, 1, 0), by: 0.08)),
            toSide: SIMD3(1, 0, 0)
        )
        var fixed: [Int: simd_quatd] = [body: pelvisCorrection, head: headCorrection, neck: simd_slerp(chestCorrection, headCorrection, 0.5)]
        for (step, joint) in spine.enumerated() {
            fixed[joint] = simd_slerp(pelvisCorrection, chestCorrection, Double(step + 1) / Double(spine.count))
        }

        let footTargets = [targets.leftFoot, targets.rightFoot]
        var legOf: [Int: (chain: Chain, side: Int)] = [:]
        for (side, chain) in legs.enumerated() {
            legOf[chain.upper] = (chain, side)
            legOf[chain.lower] = (chain, side)
            legOf[chain.end] = (chain, side)
        }
        var armOf: [Int: (chain: Chain, side: Int)] = [:]
        for (side, chain) in arms.enumerated() {
            armOf[chain.upper] = (chain, side)
            armOf[chain.lower] = (chain, side)
        }
        var knees: [Int: SIMD3<Double>] = [:]
        var feet: [Int: SIMD3<Double>] = [:]
        var elbows: [Int: SIMD3<Double>] = [:]
        var wrists: [Int: SIMD3<Double>] = [:]
        var fingertips: [Int: (knuckle: Int, target: SIMD3<Double>)] = [:]
        let chest = spine[spine.count - 1]
        let rightShoulder = arms[1].upper

        for joint in order {
            let parent = parents[joint]
            let parentRotation = parent.map { rotation[$0] } ?? simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
            let parentPosition = parent.map { position[$0] } ?? .zero
            let parentDelta = parent.map { delta[$0] } ?? simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)

            // By default a joint rides its parent.
            position[joint] = parentPosition + parentRotation.act(restLocalTranslation[joint])
            rotation[joint] = simd_normalize(parentDelta * restGlobalRotation[joint])

            if joint == body {
                position[joint] = targets.pelvis
            }
            if let correction = fixed[joint] {
                rotation[joint] = simd_normalize(correction * restGlobalRotation[joint])
            }

            if let (chain, side) = legOf[joint] {
                if joint == chain.upper {
                    let hip = position[joint]
                    let reach = chain.upperLength + chain.lowerLength - 1e-4
                    var target = footTargets[side]
                    if simd_distance(target, hip) > reach {
                        // Out of reach: the heel lifts rather than the foot tearing from the shin.
                        target = hip + simd_normalize(target - hip) * reach
                    }
                    let knee = Self.knee(root: hip, end: target, upper: chain.upperLength, lower: chain.lowerLength, bendToward: SIMD3(0, 0, 1))
                    knees[joint] = knee
                    feet[chain.end] = target
                    rotation[joint] = aim(joint, child: chain.lower, toward: knee - hip, carriedBy: parentDelta)
                } else if joint == chain.lower, let knee = knees[chain.upper], let foot = feet[chain.end] {
                    rotation[joint] = aim(joint, child: chain.end, toward: foot - knee, carriedBy: parentDelta)
                } else if joint == chain.end, let foot = feet[joint] {
                    position[joint] = foot
                    rotation[joint] = simd_normalize(footCorrections[side] * restGlobalRotation[joint])
                }
            }

            if let (chain, side) = armOf[joint] {
                let sign: Double = side == 0 ? 1 : -1
                if joint == chain.upper, let hold = targets.carry {
                    let chestTurn = delta[chest]
                    // The right shoulder rides its clavicle, so it is known here for either arm.
                    let shoulderPosition = position[parents[rightShoulder] ?? rightShoulder]
                        + rotation[parents[rightShoulder] ?? rightShoulder].act(restLocalTranslation[rightShoulder])
                    let seat = hold.seat(chest: position[chest], chestTurn: chestTurn, rightShoulder: shoulderPosition)
                    if var wrist = hold.wrist(side: side, seat: seat, chestTurn: chestTurn) {
                        let shoulder = position[joint]
                        let reach = chain.upperLength + chain.lowerLength - 1e-4
                        if simd_distance(wrist, shoulder) > reach {
                            wrist = shoulder + simd_normalize(wrist - shoulder) * reach
                        }
                        let elbow = Self.knee(root: shoulder, end: wrist, upper: chain.upperLength, lower: chain.lowerLength,
                                              bendToward: hold.elbowPole(side: side, chestTurn: chestTurn))
                        elbows[joint] = elbow
                        wrists[chain.lower] = wrist
                        if let knuckle = knuckles[side], let target = hold.fingers(side: side, seat: seat, chestTurn: chestTurn) {
                            fingertips[chain.end] = (knuckle, target)
                        }
                    }
                }
                if joint == chain.upper, let elbow = elbows[joint] {
                    rotation[joint] = aim(joint, child: chain.lower, toward: elbow - position[joint], carriedBy: parentDelta)
                } else if joint == chain.lower, let wrist = wrists[joint] {
                    rotation[joint] = aim(joint, child: chain.end, toward: wrist - position[joint], carriedBy: parentDelta)
                } else {
                    let directions = Self.armDirections(sign: sign, targets: targets)
                    if joint == chain.upper {
                        rotation[joint] = aim(joint, child: chain.lower, toward: directions.upper, carriedBy: parentDelta)
                    } else {
                        rotation[joint] = aim(joint, child: chain.end, toward: directions.forearm, carriedBy: parentDelta)
                    }
                }
            }

            if let fingers = fingertips[joint] {
                rotation[joint] = aim(joint, child: fingers.knuckle, toward: fingers.target - position[joint], carriedBy: parentDelta)
            }

            delta[joint] = simd_normalize(rotation[joint] * restGlobalRotation[joint].inverse)
        }

        return (0..<jointCount).map { joint in
            guard let parent = parents[joint] else {
                return LocalTransform(translation: SIMD3<Float>(position[joint]), rotation: rotation[joint].float)
            }
            let inverse = rotation[parent].inverse
            return LocalTransform(
                translation: SIMD3<Float>(inverse.act(position[joint] - position[parent])),
                rotation: simd_normalize(inverse * rotation[joint]).float
            )
        }
    }

    /// Where a free arm's upper arm and forearm point, in model space: swinging with the stride.
    static func armDirections(sign: Double, targets: MountainAthletePoseTargets) -> (upper: SIMD3<Double>, forearm: SIMD3<Double>) {
        let swing = targets.leftArmSwing * sign
        let upper = simd_normalize(SIMD3(sign * 0.2, -cos(swing), sin(swing)) + SIMD3(0, 0, 0.05))
        let bend = targets.elbowBend + max(swing, 0) * 0.4
        return (upper, simd_normalize(rotate(upper, towards: SIMD3(0, 0.15, 1), by: bend)))
    }

    /// Model-space positions of every joint for a pose, by forward kinematics over the local
    /// transforms `pose` returns - what the renderer will actually draw.
    func globalPositions(of local: [LocalTransform]) -> [SIMD3<Double>] {
        var position = [SIMD3<Double>](repeating: .zero, count: jointCount)
        var rotation = [simd_quatd](repeating: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), count: jointCount)
        for joint in order {
            let transform = local[joint]
            let r = transform.rotation.double, t = SIMD3<Double>(transform.translation)
            if let parent = parents[joint] {
                position[joint] = position[parent] + rotation[parent].act(t)
                rotation[joint] = rotation[parent] * r
            } else {
                position[joint] = t
                rotation[joint] = r
            }
        }
        return position
    }

    /// Where one joint is in model space for a pose, and how far it has turned from rest: what an
    /// item riding that joint is carried by.
    struct JointFrame: Equatable, Sendable {
        let position: SIMD3<Double>
        /// The joint's turn from its rest orientation, in model space.
        let turn: simd_quatd
        /// Where the joint stands at rest, which items are authored from.
        let restPosition: SIMD3<Double>
    }

    /// The model-space frames of `joints` for a pose, by forward kinematics over the local
    /// transforms `pose` returns.
    func frames(of local: [LocalTransform], joints: [Int]) -> [JointFrame] {
        var position = [SIMD3<Double>](repeating: .zero, count: jointCount)
        var rotation = [simd_quatd](repeating: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), count: jointCount)
        for joint in order {
            let transform = local[joint]
            let r = transform.rotation.double, t = SIMD3<Double>(transform.translation)
            if let parent = parents[joint] {
                position[joint] = position[parent] + rotation[parent].act(t)
                rotation[joint] = rotation[parent] * r
            } else {
                position[joint] = t
                rotation[joint] = r
            }
        }
        return joints.map { joint in
            JointFrame(
                position: position[joint],
                turn: simd_normalize(rotation[joint] * restGlobalRotation[joint].inverse),
                restPosition: restGlobalPosition[joint]
            )
        }
    }

    /// Turns a joint so the bone toward `child` points along `direction`, taking the smallest
    /// turn from where its parent carried it, so the bone does not spin about its own length.
    private func aim(_ joint: Int, child: Int, toward direction: SIMD3<Double>, carriedBy parentDelta: simd_quatd) -> simd_quatd {
        let restDirection = simd_normalize(restGlobalPosition[child] - restGlobalPosition[joint])
        let carried = parentDelta.act(restDirection)
        let turn = Self.rotation(from: carried, to: simd_normalize(direction))
        return simd_normalize(turn * parentDelta * restGlobalRotation[joint])
    }

    // MARK: - Geometry helpers

    static func knee(root: SIMD3<Double>, end: SIMD3<Double>, upper: Double, lower: Double, bendToward pole: SIMD3<Double>) -> SIMD3<Double> {
        let toEnd = end - root
        let rawDistance = simd_length(toEnd)
        guard rawDistance > 1e-6 else { return root + SIMD3(0, -upper, 0) }
        let direction = toEnd / rawDistance
        let distance = min(max(rawDistance, abs(upper - lower) + 1e-4), upper + lower - 1e-4)
        let along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
        let height = sqrt(max(upper * upper - along * along, 0))
        var bend = pole - direction * simd_dot(pole, direction)
        let length = simd_length(bend)
        bend = length > 1e-6 ? bend / length : SIMD3(0, 0, 1)
        return root + direction * along + bend * height
    }

    static func rotation(from a: SIMD3<Double>, to b: SIMD3<Double>) -> simd_quatd {
        let d = simd_dot(a, b)
        if d > 1 - 1e-9 { return simd_quatd(ix: 0, iy: 0, iz: 0, r: 1) }
        if d < -1 + 1e-9 {
            var axis = simd_cross(SIMD3(1, 0, 0), a)
            if simd_length(axis) < 1e-6 { axis = simd_cross(SIMD3(0, 1, 0), a) }
            return simd_quatd(angle: .pi, axis: simd_normalize(axis))
        }
        return simd_quatd(from: a, to: b)
    }

    /// The rotation taking one up/side frame onto another.
    static func align(fromUp: SIMD3<Double>, fromSide: SIMD3<Double>, toUp: SIMD3<Double>, toSide: SIMD3<Double>) -> simd_quatd {
        func frame(_ up: SIMD3<Double>, _ side: SIMD3<Double>) -> simd_double3x3 {
            let u = simd_normalize(up)
            let s = simd_normalize(side - u * simd_dot(side, u))
            return simd_double3x3(columns: (s, u, simd_cross(s, u)))
        }
        let from = frame(fromUp, fromSide), to = frame(toUp, toSide)
        return simd_normalize(simd_quatd(to * from.transpose))
    }

    static func pitched(_ vector: SIMD3<Double>, by angle: Double) -> SIMD3<Double> {
        simd_quatd(angle: angle, axis: SIMD3(1, 0, 0)).act(vector)
    }

    static func yawed(_ vector: SIMD3<Double>, by angle: Double) -> SIMD3<Double> {
        simd_quatd(angle: angle, axis: SIMD3(0, 1, 0)).act(vector)
    }

    static func rotate(_ vector: SIMD3<Double>, towards target: SIMD3<Double>, by angle: Double) -> SIMD3<Double> {
        let axis = simd_cross(vector, target)
        guard simd_length(axis) > 1e-9 else { return vector }
        return simd_quatd(angle: angle, axis: simd_normalize(axis)).act(vector)
    }
}

extension simd_quatd {
    var float: simd_quatf {
        simd_quatf(ix: Float(imag.x), iy: Float(imag.y), iz: Float(imag.z), r: Float(real))
    }
}

extension simd_quatf {
    var double: simd_quatd {
        simd_quatd(ix: Double(imag.x), iy: Double(imag.y), iz: Double(imag.z), r: Double(real))
    }
}
