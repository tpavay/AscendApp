import Foundation

#if canImport(CoreMotion)
import CoreMotion
#endif

struct HeadphoneMotionVector: Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double

    static let zero = HeadphoneMotionVector(x: 0, y: 0, z: 0)
}

struct HeadphoneMotionAttitude: Equatable, Sendable {
    let pitch: Double
    let roll: Double
    let yaw: Double

    static let zero = HeadphoneMotionAttitude(pitch: 0, roll: 0, yaw: 0)
}

struct HeadphoneMotionSample: Equatable, Sendable {
    let timestamp: TimeInterval
    let userAcceleration: HeadphoneMotionVector
    let rotationRate: HeadphoneMotionVector
    let gravity: HeadphoneMotionVector
    let attitude: HeadphoneMotionAttitude

    init(
        timestamp: TimeInterval,
        userAcceleration: HeadphoneMotionVector,
        rotationRate: HeadphoneMotionVector = .zero,
        gravity: HeadphoneMotionVector,
        attitude: HeadphoneMotionAttitude = .zero
    ) {
        self.timestamp = timestamp
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
        self.gravity = gravity
        self.attitude = attitude
    }
}

#if canImport(CoreMotion)
extension HeadphoneMotionSample {
    init(timestamp: TimeInterval, motion: CMDeviceMotion) {
        self.init(
            timestamp: timestamp,
            userAcceleration: HeadphoneMotionVector(
                x: motion.userAcceleration.x,
                y: motion.userAcceleration.y,
                z: motion.userAcceleration.z
            ),
            rotationRate: HeadphoneMotionVector(
                x: motion.rotationRate.x,
                y: motion.rotationRate.y,
                z: motion.rotationRate.z
            ),
            gravity: HeadphoneMotionVector(
                x: motion.gravity.x,
                y: motion.gravity.y,
                z: motion.gravity.z
            ),
            attitude: HeadphoneMotionAttitude(
                pitch: motion.attitude.pitch,
                roll: motion.attitude.roll,
                yaw: motion.attitude.yaw
            )
        )
    }
}
#endif
