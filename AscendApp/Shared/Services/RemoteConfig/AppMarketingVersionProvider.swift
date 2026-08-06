import Foundation

struct AppMarketingVersionProvider: Sendable {
    static let mainBundle = AppMarketingVersionProvider {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private let readValue: @Sendable () -> String?

    init(readValue: @escaping @Sendable () -> String?) {
        self.readValue = readValue
    }

    func currentVersion() -> String? {
        readValue()
    }
}
