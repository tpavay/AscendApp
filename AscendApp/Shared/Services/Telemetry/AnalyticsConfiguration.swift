import Foundation

struct AnalyticsConfiguration: Equatable {
    enum ValidationError: Error, Equatable {
        case incompleteDestination
        case environmentProjectMismatch
        case simulatorCannotReachProduction
    }

    static let live = AnalyticsConfiguration()

    static let mixpanelTokenInfoKey = "AscendMixpanelToken"
    static let mixpanelProjectIDInfoKey = "AscendMixpanelProjectID"

    let mixpanelToken: String?
    let mixpanelProjectID: String?

    var canConfigureMixpanel: Bool {
        mixpanelToken != nil && mixpanelProjectID != nil
    }

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        mixpanelToken = Self.normalizedToken(infoDictionary[Self.mixpanelTokenInfoKey])
        mixpanelProjectID = Self.normalizedProjectID(infoDictionary[Self.mixpanelProjectIDInfoKey])
    }

    /// Takes a validated envelope so the environment and build configuration
    /// have already been proven to agree; this only maps the environment to the
    /// one Mixpanel project allowed to receive it.
    func validatedMixpanelToken(
        for envelope: TelemetryEnvelope,
        runtime: TelemetryRuntimeEnvironment = .current
    ) throws -> String? {
        guard mixpanelToken != nil || mixpanelProjectID != nil else {
            return nil
        }
        guard let mixpanelToken, let mixpanelProjectID else {
            throw ValidationError.incompleteDestination
        }

        let expectedProjectID: String? = switch envelope.appEnvironment {
        case "dev": "4032860"
        case "staging": "4051102"
        case "production": "4051100"
        default: nil
        }

        guard mixpanelProjectID == expectedProjectID else {
            throw ValidationError.environmentProjectMismatch
        }

        // The environment/project pair agreeing is not enough on its own: a Release binary
        // compiled for the simulator SDK reports `production` exactly like a customer's, so the
        // build configuration cannot separate a rehearsal from a real climber. Production numbers
        // describe people who bought the app; staging is where a session is reproduced.
        guard envelope.appEnvironment != "production" || runtime.isSimulator == false else {
            throw ValidationError.simulatorCannotReachProduction
        }

        return mixpanelToken
    }

    private static func normalizedToken(_ value: Any?) -> String? {
        guard let rawValue = value as? String else { return nil }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, !trimmedValue.hasPrefix("$(") else {
            return nil
        }

        return trimmedValue
    }

    private static func normalizedProjectID(_ value: Any?) -> String? {
        guard let rawValue = value as? String else { return nil }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.isEmpty == false, trimmedValue.hasPrefix("$(") == false else {
            return nil
        }

        return trimmedValue
    }
}
