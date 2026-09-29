import RealityKit
import SwiftUI

/// The Ascend Mountain world: RealityKit renders the staircase, athlete and sky; everything the
/// climber reads sits in SwiftUI on top (spec 5).
///
/// `stepSource` is read once per rendered frame and is the scene's only input, so the view can
/// be dropped and recreated freely - it resumes on the stair the count says, never from zero.
struct AscendMountainRealityView: View {
    @State private var controller: MountainSceneController

    init(
        seed: UInt64,
        stepSource: @escaping @MainActor () -> Int,
        debugState: MountainDebugState? = nil,
        worldSource: @escaping @Sendable () throws -> MountainWorld = { try MountainWorld.bundled() },
        ghosts: [MountainGhost] = [],
        emphasis: MountainClimberEmphasis = .none,
        elapsedSource: (@MainActor () -> TimeInterval)? = nil
    ) {
        _controller = State(
            initialValue: MountainSceneController(
                seed: seed,
                stepSource: stepSource,
                debugState: debugState,
                worldSource: worldSource,
                ghosts: ghosts,
                emphasis: emphasis,
                elapsedSource: elapsedSource
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
