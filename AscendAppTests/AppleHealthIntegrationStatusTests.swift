import Testing
@testable import AscendApp

/// The Settings card answers from both halves of the Health connection, so it never promises an
/// import the climber has not granted, or one the kill switch has turned off.
@MainActor
struct AppleHealthIntegrationStatusTests {
    @Test
    func connectedForBothOffersImportsAndManage() {
        let status = AppleHealthIntegrationStatus(enrichment: .connected, importState: .connected)
        #expect(status.label == "Connected")
        #expect(status.action == .manage)
        #expect(status.message.contains("import as climbs"))
    }

    /// Connected before 1.3.0: heart rate arrives, workouts were never asked for.
    @Test
    func connectedBeforeImportReturnedOffersConnectAndPromisesNoImport() {
        let status = AppleHealthIntegrationStatus(enrichment: .connected, importState: .neverConnected)
        #expect(status.action == .connect)
        #expect(status.label == nil)
        #expect(!status.message.contains("import as climbs"))
        #expect(status.message.contains("Heart rate and calories attach"))
        #expect(status.message.contains("Connect to bring in stair stepper workouts"))
    }

    @Test
    func withTheKillSwitchOffNothingMentionsImport() {
        let connected = AppleHealthIntegrationStatus(enrichment: .connected, importState: nil)
        #expect(connected.action == .manage)
        #expect(connected.label == "Connected")
        #expect(!connected.message.localizedStandardContains("workouts"))

        let notConnected = AppleHealthIntegrationStatus(enrichment: .neverConnected, importState: nil)
        #expect(notConnected.action == .connect)
        #expect(!notConnected.message.localizedStandardContains("workouts"))
    }

    @Test
    func neverConnectedOffersConnectForBoth() {
        let status = AppleHealthIntegrationStatus(enrichment: .neverConnected, importState: .neverConnected)
        #expect(status.action == .connect)
        #expect(status.message.contains("stair stepper workouts"))
        #expect(status.message.contains("heart rate"))
    }

    @Test
    func revokedAndUnavailableKeepTheirOwnAnswers() {
        let revoked = AppleHealthIntegrationStatus(enrichment: .revoked, importState: .neverConnected)
        #expect(revoked.label == "Permissions Disabled")
        #expect(revoked.tone == .disabled)
        #expect(revoked.action == .manage)

        let unavailable = AppleHealthIntegrationStatus(enrichment: .unavailable, importState: nil)
        #expect(unavailable.action == .none)
        #expect(unavailable.message == "Apple Health is not available on this device.")
    }
}
