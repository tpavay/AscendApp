import Foundation

enum AppVersionPolicy {
    /// Resolves the update presentation from whichever thresholds parse.
    ///
    /// Each threshold is judged on its own. An unparseable current version fails the whole
    /// evaluation open, because nothing can be compared against it, but an unparseable or absent
    /// recommendation must never veto a minimum an operator armed - the lower-stakes value would
    /// otherwise be able to silently disable the safety gate.
    static func evaluate(
        currentVersion: String?,
        minimumSupportedVersion: String?,
        recommendedVersion: String?
    ) -> AppUpdatePresentation? {
        guard let current = SemanticAppVersion(currentVersion) else { return nil }

        if let minimum = SemanticAppVersion(minimumSupportedVersion), current < minimum {
            return .required
        }
        if let recommended = SemanticAppVersion(recommendedVersion), current < recommended {
            return .recommended
        }
        return nil
    }
}
