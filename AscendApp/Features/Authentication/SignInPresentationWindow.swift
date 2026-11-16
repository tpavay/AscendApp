import UIKit

@MainActor
protocol SignInPresentationWindowCandidate: AnyObject {
    var isKeyWindow: Bool { get }
}

@MainActor
protocol SignInPresentationSceneCandidate {
    associatedtype Window: SignInPresentationWindowCandidate
    var activationState: UIScene.ActivationState { get }
    var keyWindow: Window? { get }
    var windows: [Window] { get }
}

extension UIWindow: SignInPresentationWindowCandidate {}
extension UIWindowScene: SignInPresentationSceneCandidate {}

/// The window a sign-in provider presents over, shared by Google Sign-In and
/// Sign in with Apple so both land on the same screen.
///
/// `connectedScenes.first` is an unordered set's first element and
/// `windows.first` is not necessarily the key window, so a naive lookup can
/// land on a background scene - or on no window at all - and refuse a sign-in
/// the app was perfectly able to present (Sentry ASCEND-IOS-2W). Scenes are
/// tried foreground-active first, then foreground-inactive, then background,
/// and within a scene its key window wins.
@MainActor
enum SignInPresentationWindow {
    static let sceneOrder: [UIScene.ActivationState] = [.foregroundActive, .foregroundInactive, .background]

    /// One window per scene that has any, most suitable first.
    static func candidates<Scene: SignInPresentationSceneCandidate>(in scenes: [Scene]) -> [Scene.Window] {
        sceneOrder.flatMap { state in
            scenes.filter { $0.activationState == state }
        }
        .compactMap { scene in
            scene.keyWindow ?? scene.windows.first { $0.isKeyWindow } ?? scene.windows.first
        }
    }

    static func connectedCandidates() -> [UIWindow] {
        candidates(in: UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene })
    }
}
