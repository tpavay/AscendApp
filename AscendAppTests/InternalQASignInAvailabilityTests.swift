import Testing
@testable import AscendApp

struct InternalQASignInAvailabilityTests {
    @Test
    func enabledOnlyForDevAndStagingFirebaseProjects() {
        #expect(InternalQASignInAvailability.isEnabled(projectID: "ascend-f2e4f"))
        #expect(InternalQASignInAvailability.isEnabled(projectID: "ascend-staging-fa7d5"))
        #expect(InternalQASignInAvailability.isEnabled(projectID: "ascend-prod-9c8f2") == false)
        #expect(InternalQASignInAvailability.isEnabled(projectID: nil) == false)
    }
}
