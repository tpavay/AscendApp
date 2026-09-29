import RealityKit
import SwiftUI

/// The Ascend Mountain world: RealityKit renders the staircase, athlete and sky; everything the
/// climber reads sits in SwiftUI on top (spec 5).
///
/// `stepSource`, `ghostSource`, `markerSource` and `athleteLook` are read once per rendered frame
/// and are the scene's only inputs, so the view can be dropped and recreated freely - it resumes on
/// the stair the count says, never from zero, with whoever is racing at that moment. `journeySource`
/// says where on the mountain the climb began; the scene follows it only while the climber is on the
/// start line. `packReport` hears how many racers are drawn either side of the climber whenever
/// that changes.
struct AscendMountainRealityView: View {
    @State private var controller: MountainSceneController

    init(
        seed: UInt64,
        stepSource: @escaping @MainActor () -> Int,
        debugState: MountainDebugState? = nil,
        worldSource: @escaping @Sendable () throws -> MountainWorld = { try MountainWorld.bundled() },
        ghostSource: @escaping @MainActor () -> [MountainGhost] = { [] },
        markerSource: @escaping @MainActor () -> [MountainMarker] = { [] },
        elapsedSource: (@MainActor () -> TimeInterval)? = nil,
        athleteLook: @escaping @MainActor () -> AthleteLook = { .starting(for: nil) },
        journeySource: @escaping @MainActor () -> Int = { 0 },
        cameraTuning: MountainSceneDirector.CameraTuning = .standard,
        packLimits: MountainPack.Limits = .init(),
        packReport: (@MainActor (MountainPack.Drawn) -> Void)? = nil
    ) {
        _controller = State(
            initialValue: MountainSceneController(
                seed: seed,
                stepSource: stepSource,
                debugState: debugState,
                worldSource: worldSource,
                ghostSource: ghostSource,
                markerSource: markerSource,
                elapsedSource: elapsedSource,
                athleteLook: athleteLook,
                packLimits: packLimits,
                packReport: packReport,
                journeySource: journeySource,
                cameraTuning: cameraTuning
            )
        )
    }

    var body: some View {
        let controller = controller
        RealityView { content in
            await controller.install(in: &content)
        } placeholder: {
            Color.black
        }
        .onDisappear {
            controller.stop()
        }
        .accessibilityHidden(true)
    }
}
