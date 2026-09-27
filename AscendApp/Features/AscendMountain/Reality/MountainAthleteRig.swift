import RealityKit
import UIKit
import simd

/// The placeholder athlete: primitive shapes posed every frame from `MountainAthleteKinematics`.
///
/// Deliberately plain - spec 6 asks for an ugly engineering prototype - but its joints follow
/// the real stride, so the feel of the step-to-stair link can be judged now and a rigged model
/// can later take the same inputs.
@MainActor
final class MountainAthleteRig {
    let root = Entity()

    private let torso: ModelEntity
    private let head: ModelEntity
    private let thighs: [ModelEntity]
    private let shins: [ModelEntity]
    private let feet: [ModelEntity]
    private let arms: [ModelEntity]

    private static let torsoLength: Float = 0.56
    private static let armLength: Float = 0.6
    private static let hipHalfWidth: Double = 0.1
    private static let shoulderHalfWidth: Float = 0.225

    init() {
        let kit = SimpleMaterial(color: UIColor(red: 0.53, green: 0.83, blue: 0.04, alpha: 1), roughness: 0.6, isMetallic: false)
        let tights = SimpleMaterial(color: UIColor(white: 0.16, alpha: 1), roughness: 0.8, isMetallic: false)
        let skin = SimpleMaterial(color: UIColor(red: 0.8, green: 0.64, blue: 0.52, alpha: 1), roughness: 0.7, isMetallic: false)
        let shoe = SimpleMaterial(color: UIColor(white: 0.97, alpha: 1), roughness: 0.5, isMetallic: false)

        torso = ModelEntity(mesh: .generateBox(size: [0.36, Self.torsoLength, 0.2], cornerRadius: 0.07), materials: [kit])
        head = ModelEntity(mesh: .generateSphere(radius: 0.12), materials: [skin])
        let thighMesh = MeshResource.generateCylinder(height: Float(MountainAthleteKinematics.thighLength), radius: 0.075)
        let shinMesh = MeshResource.generateCylinder(height: Float(MountainAthleteKinematics.shinLength), radius: 0.06)
        let footMesh = MeshResource.generateBox(size: [0.11, 0.08, 0.26], cornerRadius: 0.03)
        let armMesh = MeshResource.generateCylinder(height: Self.armLength, radius: 0.045)
        thighs = (0..<2).map { _ in ModelEntity(mesh: thighMesh, materials: [tights]) }
        shins = (0..<2).map { _ in ModelEntity(mesh: shinMesh, materials: [tights]) }
        feet = (0..<2).map { _ in ModelEntity(mesh: footMesh, materials: [shoe]) }
        arms = (0..<2).map { _ in ModelEntity(mesh: armMesh, materials: [skin]) }

        for part in [torso, head] + thighs + shins + feet + arms {
            root.addChild(part)
        }
    }

    /// Poses every part in render space. `origin` is the course point at the render origin.
    func apply(_ kinematics: MountainAthleteKinematics, origin: SIMD3<Double>) {
        func render(_ point: SIMD3<Double>) -> SIMD3<Float> {
            SIMD3<Float>(point - origin)
        }

        let pose = kinematics.bodyPose
        let forward = pose.forward
        let right = pose.right
        let heading = Float(pose.heading)
        let yaw = simd_quatf(angle: heading, axis: [0, 1, 0])

        // Legs: hip -> knee -> foot, knees bending forward.
        let footTargets = [kinematics.leftFoot, kinematics.rightFoot]
        for (side, sign) in [(0, -1.0), (1, 1.0)] {
            let hip = kinematics.hipCentre + right * (sign * Self.hipHalfWidth)
            let ankle = footTargets[side] + SIMD3(0, 0.07, 0)
            let knee = MountainAthleteKinematics.knee(hip: hip, foot: ankle, forward: forward)
            place(thighs[side], from: render(hip), to: render(knee))
            place(shins[side], from: render(knee), to: render(ankle))
            feet[side].position = render(footTargets[side] + SIMD3(0, 0.04, 0) + forward * 0.04)
            feet[side].orientation = yaw
        }

        // Torso leans forward from the hips; head and shoulders ride on it.
        let lean = Float(kinematics.torsoLean)
        let torsoRotation = yaw * simd_quatf(angle: -lean, axis: [1, 0, 0])
        let spine = torsoRotation.act([0, 1, 0])
        let hipCentre = render(kinematics.hipCentre)
        torso.position = hipCentre + spine * (Self.torsoLength / 2 + 0.02)
        torso.orientation = torsoRotation
        head.position = hipCentre + spine * (Self.torsoLength + 0.17)

        let renderRight = SIMD3<Float>(right)
        let renderForward = SIMD3<Float>(forward)
        let shoulderCentre = hipCentre + spine * (Self.torsoLength - 0.04)
        for (side, sign) in [(0, Float(-1)), (1, Float(1))] {
            let swing = Float(kinematics.leftArmSwing) * (side == 0 ? 1 : -1)
            let shoulder = shoulderCentre + renderRight * (sign * Self.shoulderHalfWidth)
            let armDirection = simd_normalize(SIMD3<Float>(0, -cos(swing), 0) + renderForward * sin(swing))
            place(arms[side], from: shoulder, to: shoulder + armDirection * Self.armLength)
        }
    }

    /// Stretches a Y-axis cylinder between two render-space points.
    private func place(_ entity: ModelEntity, from start: SIMD3<Float>, to end: SIMD3<Float>) {
        let span = end - start
        let length = simd_length(span)
        entity.position = (start + end) / 2
        guard length > 1e-5 else { return }
        entity.orientation = simd_quatf(from: [0, 1, 0], to: span / length)
    }
}
