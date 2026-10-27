@preconcurrency import CoreMotion
import Foundation

/// The phone's own count of steps across a window, from the motion coprocessor, which keeps
/// counting while the app is dead and is read back at resume.
///
/// It is an estimate of the phone's movement, not the machine's step count, and the two can differ
/// by a lot on a stair stepper where the phone sits in a cradle. It is offered as a default to
/// correct, labelled as the phone's, and never written on its own authority.
protocol PhoneStepEstimating: Sendable {
    func steps(from start: Date, to end: Date) async -> Int?
}

final class CMPedometerStepEstimator: PhoneStepEstimating, @unchecked Sendable {
    static let shared = CMPedometerStepEstimator()

    private let pedometer = CMPedometer()

    func steps(from start: Date, to end: Date) async -> Int? {
        guard CMPedometer.isStepCountingAvailable(), end > start else { return nil }

        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue)
            }
        }
    }
}

/// A phone with no coprocessor answer, for tests and for a simulator.
struct NoPhoneStepEstimator: PhoneStepEstimating {
    func steps(from start: Date, to end: Date) async -> Int? { nil }
}
