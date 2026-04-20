import Foundation

struct InternalQALocalCredentialsLoader {
    static let emailEnvironmentKey = "ASC_INTERNAL_QA_EMAIL"
    static let passwordEnvironmentKey = "ASC_INTERNAL_QA_PASSWORD"

    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func load() -> InternalQALocalCredentials? {
        let email = (environment[Self.emailEnvironmentKey] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let password = environment[Self.passwordEnvironmentKey] ?? ""

        guard !email.isEmpty else { return nil }
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        return InternalQALocalCredentials(
            email: email,
            password: password
        )
    }
}
