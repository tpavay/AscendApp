import Darwin
import Foundation
import Observation

/// What the developer overlay reads and the one knob it turns (spec 41).
///
/// The scene publishes here a few times a second rather than every frame, so the overlay costs
/// the renderer nothing. Only a Dev build ever creates one; without it the scene publishes
/// nothing and applies no offset.
@MainActor
@Observable
final class MountainDebugState {
    struct Metrics: Equatable {
        var framesPerSecond = 0.0
        var logicalSteps = 0
        var visualSteps = 0.0
        var renderCadenceStepsPerMinute = 0.0
        var animationPlaybackRate = 0.0
        var animationIntensity = 0.0
        var activeChunks = 0
        var idleChunkSlots = 0
        var chunkRecycles = 0
        var chunkIndex = 0
        var chunkKind = ""
        var virtualAltitudeMetres = 0.0
        var renderOriginDistanceMetres = 0.0
        var biome = "-"
        var ghostCount = 0
        var residentMemoryMegabytes: Double?
    }

    var metrics = Metrics()
    /// Added to the workout's step count before the scene sees it, so very large climbs can be
    /// exercised on a device. It moves the picture only: the workout's own count is untouched.
    var visualStepOffset = 0

    static func residentMemoryMegabytes() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }
}
