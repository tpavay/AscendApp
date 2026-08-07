import Foundation
import Observation

/// The app-wide presentation state produced by a successfully resolved Remote Config fetch.
@MainActor
@Observable
final class AppVersionGateState {
    static let shared = AppVersionGateState()

    var presentation: AppUpdatePresentation?

    init(presentation: AppUpdatePresentation? = nil) {
        self.presentation = presentation
    }

    func resolve(currentVersion: String?, remoteValues: [String: String]) {
        presentation = AppVersionPolicy.evaluate(
            currentVersion: currentVersion,
            minimumSupportedVersion: remoteValues[RemoteAppVersionParameter.minimumSupported.key],
            recommendedVersion: remoteValues[RemoteAppVersionParameter.recommended.key]
        )
    }

    /// A failed fetch cannot make a persisted or default threshold authoritative for this pass.
    ///
    /// It also cannot repeal a lockout a successful fetch already resolved. Losing the network is
    /// not evidence that this build became supported again, and treating it as such would let a
    /// climber below the minimum clear the non-dismissible sheet by foregrounding in aeroplane mode.
    func failOpen() {
        guard presentation != .required else { return }
        presentation = nil
    }

    func dismissRecommended() {
        guard presentation == .recommended else { return }
        presentation = nil
    }
}
