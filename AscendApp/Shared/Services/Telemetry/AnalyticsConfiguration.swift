import Foundation

struct AnalyticsConfiguration: Equatable {
    static let live = AnalyticsConfiguration()

    static let mixpanelTokenInfoKey = "AscendMixpanelToken"

    let mixpanelToken: String?

    var canConfigureMixpanel: Bool {
        mixpanelToken != nil
    }

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        mixpanelToken = Self.normalizedToken(infoDictionary[Self.mixpanelTokenInfoKey])
    }

    private static func normalizedToken(_ value: Any?) -> String? {
        guard let rawValue = value as? String else { return nil }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, !trimmedValue.hasPrefix("$(") else {
            return nil
        }

        return trimmedValue
    }
}
