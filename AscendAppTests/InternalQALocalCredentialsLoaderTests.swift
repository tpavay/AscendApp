import Testing
@testable import AscendApp

struct InternalQALocalCredentialsLoaderTests {
    @Test
    func loadReturnsCredentialsWhenBothEnvironmentValuesExist() {
        let loader = InternalQALocalCredentialsLoader(
            environment: [
                InternalQALocalCredentialsLoader.emailEnvironmentKey: " qa-smoke@example.com ",
                InternalQALocalCredentialsLoader.passwordEnvironmentKey: "secret-value"
            ]
        )

        let credentials = loader.load()

        #expect(credentials == InternalQALocalCredentials(
            email: "qa-smoke@example.com",
            password: "secret-value"
        ))
    }

    @Test
    func loadReturnsNilWhenEitherEnvironmentValueIsMissing() {
        let missingEmailLoader = InternalQALocalCredentialsLoader(
            environment: [
                InternalQALocalCredentialsLoader.passwordEnvironmentKey: "secret-value"
            ]
        )
        let missingPasswordLoader = InternalQALocalCredentialsLoader(
            environment: [
                InternalQALocalCredentialsLoader.emailEnvironmentKey: "qa-smoke@example.com"
            ]
        )

        #expect(missingEmailLoader.load() == nil)
        #expect(missingPasswordLoader.load() == nil)
    }
}
