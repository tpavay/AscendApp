import Foundation
import simd

/// Where the athlete's body, feet and limbs go for a given visual step count, in course space.
///
/// The stride is taken from the step count itself rather than from a clock: each real step
/// carries one foot from two stairs below the other to one stair above it, and the body rises
/// one stair with it. A foot therefore lands on its tread exactly as the body arrives, at any
/// speed, and cannot slide - the animation plays faster only because the steps do.
struct MountainAthleteKinematics: Equatable, Sendable {
    static let hipHeight = 0.84
    static let footSpacing = 0.14
    static let thighLength = 0.46
    static let shinLength = 0.46

    let bodyPose: MountainPose
    let hipCentre: SIMD3<Double>
    let leftFoot: SIMD3<Double>
    let rightFoot: SIMD3<Double>
    /// Forward lean of the torso, radians.
    let torsoLean: Double
    /// Shoulder swing of the left arm, radians forward; the right arm mirrors it.
    let leftArmSwing: Double

    /// - Parameters:
    ///   - visualSteps: the follower's smoothed step count.
    ///   - intensity: `MountainAnimationPacing.intensity`, already smoothed by the caller.
    ///   - movement: 0 standing still to 1 climbing, smoothed by the caller.
    ///   - time: seconds, only for the idle breath.
    ///   - pose: resolves a (possibly fractional) step count to a course pose.
    init(
        visualSteps: Double,
        intensity: Double,
        movement: Double,
        time: Double,
        pose: (Double) -> MountainPose
    ) {
        let wholeStep = visualSteps.rounded(.down)
        let stride = visualSteps - wholeStep
        let eased = stride * stride * (3 - 2 * stride)
        let clampedIntensity = min(max(intensity, 0), 1)
        let clampedMovement = min(max(movement, 0), 1)

        // Treads alternate feet: even treads take the left foot, odd treads the right.
        let stanceTread = wholeStep
        let stanceIsLeft = Int(stanceTread).isMultiple(of: 2)
        let stanceFoot = Self.footPosition(onTread: stanceTread, isLeft: stanceIsLeft, pose: pose)
        let swingFrom = Self.footPosition(onTread: stanceTread - 1, isLeft: !stanceIsLeft, pose: pose)
        let swingTo = Self.footPosition(onTread: stanceTread + 1, isLeft: !stanceIsLeft, pose: pose)
        let lift = (0.06 + 0.06 * clampedIntensity) * sin(.pi * stride)
        let swingFoot = swingFrom + (swingTo - swingFrom) * eased + SIMD3(0, lift, 0)

        leftFoot = stanceIsLeft ? stanceFoot : swingFoot
        rightFoot = stanceIsLeft ? swingFoot : stanceFoot

        // The body sits over the middle of its two feet: half a step behind the leading tread.
        bodyPose = pose(visualSteps - 0.5)
        let breath = (1 - clampedMovement) * 0.008 * sin(time * 2 * .pi / 3.4)
        let bob = clampedMovement * 0.025 * clampedIntensity * cos(2 * .pi * stride)
        hipCentre = bodyPose.position + SIMD3(0, Self.hipHeight - 0.04 * clampedMovement + breath + bob, 0)

        torsoLean = 0.08 + clampedMovement * (0.06 + 0.14 * clampedIntensity)
        let swingDirection: Double = stanceIsLeft ? 1 : -1
        leftArmSwing = swingDirection * clampedMovement * (0.25 + 0.45 * clampedIntensity) * sin(.pi * stride)
    }

    private static func footPosition(onTread tread: Double, isLeft: Bool, pose: (Double) -> MountainPose) -> SIMD3<Double> {
        let treadPose = pose(tread)
        return treadPose.position + treadPose.right * (isLeft ? -footSpacing : footSpacing)
    }

    /// Two-bone leg solve: where the knee goes for a hip and a foot, bending toward `forward`.
    /// A foot beyond reach straightens the leg toward it rather than detaching.
    static func knee(
        hip: SIMD3<Double>,
        foot: SIMD3<Double>,
        forward: SIMD3<Double>,
        thigh: Double = thighLength,
        shin: Double = shinLength
    ) -> SIMD3<Double> {
        let toFoot = foot - hip
        let rawDistance = simd_length(toFoot)
        guard rawDistance > 1e-6 else { return hip + SIMD3(0, -thigh, 0) }

        let direction = toFoot / rawDistance
        let distance = min(max(rawDistance, abs(thigh - shin) + 1e-4), thigh + shin - 1e-4)
        let along = (thigh * thigh - shin * shin + distance * distance) / (2 * distance)
        let height = sqrt(max(thigh * thigh - along * along, 0))

        // Bend direction: `forward` with the component along the leg removed.
        var bend = forward - direction * simd_dot(forward, direction)
        let bendLength = simd_length(bend)
        bend = bendLength > 1e-6 ? bend / bendLength : SIMD3(0, 0, -1)

        return hip + direction * along + bend * height
    }
}
