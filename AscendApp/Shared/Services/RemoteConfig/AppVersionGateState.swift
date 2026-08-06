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
    func failOpen() {
        presentation = nil
    }

    func dismissRecommended() {
        guard presentation == .recommended else { return }
        presentation = nil
    }
}
