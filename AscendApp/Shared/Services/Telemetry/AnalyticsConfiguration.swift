import Foundation

struct AnalyticsConfiguration: Equatable {
    enum ValidationError: Error, Equatable {
        case incompleteDestination
        case environmentProjectMismatch
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

    func validatedMixpanelToken(for metadata: TelemetryBuildMetadata) throws -> String? {
        guard mixpanelToken != nil || mixpanelProjectID != nil else {
            return nil
        }
        guard let mixpanelToken, let mixpanelProjectID else {
            throw ValidationError.incompleteDestination
        }

        let expectedProjectID: String? = switch (metadata.appEnvironment, metadata.buildConfig) {
        case ("dev", "debug"): "4032860"
        case ("staging", "staging"): "4051102"
        case ("production", "release"): "4051100"
        default: nil
        }

        guard mixpanelProjectID == expectedProjectID else {
            throw ValidationError.environmentProjectMismatch
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
