import Foundation
import simd

/// Where the athlete's body, feet and limbs go for a given visual step count, in course space.
///
/// The stride is taken from the step count itself rather than from a clock: each real step
/// carries one foot from two stairs below the other to one stair above it, and the body rises
/// one stair with it. A foot therefore lands on its tread exactly as the body arrives, at any
/// speed, and cannot slide - the animation plays faster only because the steps do.
struct MountainAthleteKinematics: Equatable, Sendable {
    /// Pelvis height over the ground midway between the feet: knees soft, as on a stair.
    static let pelvisHeight = 0.76
    static let footSpacing = 0.12

    let bodyPose: MountainPose
    let hipCentre: SIMD3<Double>
    /// Ground contact points of each foot (tread top), in course space.
    let leftFoot: SIMD3<Double>
    let rightFoot: SIMD3<Double>
    /// Forward lean of the torso, radians.
    let torsoLean: Double
    /// Shoulder swing of the left arm, radians forward; the right arm mirrors it.
    let leftArmSwing: Double
    /// Elbow bend, radians.
    let elbowBend: Double
    /// Hip counter-twist with the stride, radians about the vertical.
    let twist: Double

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
        let clampedIntensity = min(max(intensity, 0), 1)
        let clampedMovement = min(max(movement, 0), 1)

        // Treads alternate feet: even treads take the left foot, odd treads the right.
        let stanceTread = wholeStep
        let stanceIsLeft = Int(stanceTread).isMultiple(of: 2)
        let stanceFoot = Self.footPosition(onTread: stanceTread, isLeft: stanceIsLeft, pose: pose)
        let swingFrom = Self.footPosition(onTread: stanceTread - 1, isLeft: !stanceIsLeft, pose: pose)
        let swingTo = Self.footPosition(onTread: stanceTread + 1, isLeft: !stanceIsLeft, pose: pose)

        // The swinging foot rises early and travels late, so it clears the nose of the stair it
        // passes over instead of scuffing the riser.
        let across = stride * stride * (3 - 2 * stride)
        let up = sin(stride * .pi / 2)
        let lift = (0.05 + 0.05 * clampedIntensity) * sin(.pi * stride)
        let horizontal = swingFrom + (swingTo - swingFrom) * across
        let swingFoot = SIMD3(horizontal.x, swingFrom.y + (swingTo.y - swingFrom.y) * up + lift, horizontal.z)

        leftFoot = stanceIsLeft ? stanceFoot : swingFoot
        rightFoot = stanceIsLeft ? swingFoot : stanceFoot

        // The body sits over the middle of its two feet: half a step behind the leading tread.
        bodyPose = pose(visualSteps - 0.5)
        let breath = (1 - clampedMovement) * 0.008 * sin(time * 2 * .pi / 3.4)
        let bob = clampedMovement * 0.02 * clampedIntensity * cos(2 * .pi * stride)
        hipCentre = bodyPose.position + SIMD3(0, Self.pelvisHeight - 0.03 * clampedMovement + breath + bob, 0)

        torsoLean = 0.1 + clampedMovement * (0.08 + 0.16 * clampedIntensity)
        let swingDirection: Double = stanceIsLeft ? 1 : -1
        leftArmSwing = swingDirection * clampedMovement * (0.25 + 0.4 * clampedIntensity) * sin(.pi * stride)
        elbowBend = 0.3 + clampedMovement * (0.35 + 0.7 * clampedIntensity)
        twist = -swingDirection * clampedMovement * 0.12 * sin(.pi * stride)
    }

    private static func footPosition(onTread tread: Double, isLeft: Bool, pose: (Double) -> MountainPose) -> SIMD3<Double> {
        let treadPose = pose(tread)
        return treadPose.position + treadPose.right * (isLeft ? -footSpacing : footSpacing)
    }
}
