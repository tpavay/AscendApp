import Foundation
import Observation

/// The app-wide update verdict, derived from the last version floor this device actually received.
///
/// Seeded at launch from the SDK's persisted activation and re-resolved on every successful fetch,
/// so a climber who would hit the lockout online hits it offline too. A device the backend has
/// never answered has no floor to enforce and stays open.
@MainActor
@Observable
final class AppVersionGateState {
    static let shared = AppVersionGateState()

    var presentation: AppUpdatePresentation?

    init(presentation: AppUpdatePresentation? = nil) {
        self.presentation = presentation
    }

    /// Whether this build is below the floor, and so owns ``AppRootRoute/updateRequired``.
    var isUpdateRequired: Bool {
        presentation?.locksOutApp == true
    }

    /// The verdict the root sheet may present. The lockout is deliberately absent: it is a route,
    /// so nothing presented outside `RootView` can cover it and the two can never stack.
    ///
    /// Settable because `.sheet(item:)` needs a binding. The only write a sheet makes is the `nil`
    /// of its own dismissal, which is the recommendation being dismissed; nothing arms the gate
    /// through here.
    var nudgePresentation: AppUpdatePresentation? {
        get { isUpdateRequired ? nil : presentation }
        set {
            guard newValue == nil else { return }
            dismissRecommended()
        }
    }

    func resolve(currentVersion: String?, remoteValues: [String: String]) {
        presentation = AppVersionPolicy.evaluate(
            currentVersion: currentVersion,
            minimumSupportedVersion: remoteValues[RemoteAppVersionParameter.minimumSupported.key],
            recommendedVersion: remoteValues[RemoteAppVersionParameter.recommended.key]
        )
    }

    func dismissRecommended() {
        guard presentation == .recommended else { return }
        presentation = nil
    }
}
