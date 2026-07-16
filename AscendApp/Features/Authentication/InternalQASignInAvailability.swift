import Foundation

struct InternalQASignInAvailability {
    private static let allowedProjectIDs: Set<String> = [
        "ascend-f2e4f",
        "ascend-staging-fa7d5"
    ]

    static var isBuildEnabled: Bool {
        #if DEBUG
        return true
        #elseif STAGING
        return true
        #else
        return false
        #endif
    }

    static var supportsEnvironmentCredentials: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static func isEnabled(projectID: String?) -> Bool {
        guard isBuildEnabled else { return false }
        return isAllowedProjectID(projectID)
    }

    static func isAllowedProjectID(_ projectID: String?) -> Bool {
        guard let projectID else { return false }
        return allowedProjectIDs.contains(projectID)
    }
}
