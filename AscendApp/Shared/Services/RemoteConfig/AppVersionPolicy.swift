import Foundation

enum AppVersionPolicy {
    /// Resolves the update presentation, failing open unless all three versions parse.
    static func evaluate(
        currentVersion: String?,
        minimumSupportedVersion: String?,
        recommendedVersion: String?
    ) -> AppUpdatePresentation? {
        guard let current = SemanticAppVersion(currentVersion),
              let minimum = SemanticAppVersion(minimumSupportedVersion),
              let recommended = SemanticAppVersion(recommendedVersion) else {
            return nil
        }

        if current < minimum {
            return .required
        }
        if current < recommended {
            return .recommended
        }
        return nil
    }
}
