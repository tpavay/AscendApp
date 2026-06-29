import Foundation

struct SentryConfiguration: Equatable {
    static let live = SentryConfiguration()

    static let dsnInfoKey = "AscendSentryDSN"
    static let enabledInfoKey = "AscendSentryEnabled"

    let dsn: String?
    let isExplicitlyEnabled: Bool?

    var canConfigure: Bool {
        dsn != nil && isExplicitlyEnabled != false
    }

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        dsn = Self.normalizedString(infoDictionary[Self.dsnInfoKey])
        isExplicitlyEnabled = Self.normalizedBool(infoDictionary[Self.enabledInfoKey])
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let rawValue = value as? String else { return nil }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, !trimmedValue.hasPrefix("$(") else {
            return nil
        }

        return trimmedValue
    }

    private static func normalizedBool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }

        guard let rawValue = value as? String else { return nil }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }
}
