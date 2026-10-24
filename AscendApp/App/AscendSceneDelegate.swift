import HealthKitUI
import UIKit

/// Receives the scene connection, which is where iOS 26 says whether this launch is a workout
/// recovery: the system relaunching Ascend because a workout session was running when the process
/// died (WWDC25 session 322, `UIScene.ConnectionOptions.shouldHandleActiveWorkoutRecovery`).
///
/// SwiftUI still owns the window; this delegate creates none. It exists only to read that one flag
/// and hand the relaunch to `HeadphoneSessionRelaunchCoordinator`, which reattaches the workout
/// session and restarts counting from the persisted draft with nothing on screen.
final class AscendSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        let isWorkoutRecovery = connectionOptions.shouldHandleActiveWorkoutRecovery
        Task { @MainActor in
            await HeadphoneSessionRelaunchCoordinator.shared.handleSceneConnection(
                isWorkoutRecovery: isWorkoutRecovery
            )
        }
    }
}
