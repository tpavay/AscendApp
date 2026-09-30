import Foundation
@preconcurrency import FirebaseFunctions
import Testing
@testable import AscendApp

@MainActor
struct StravaIntegrationViewModelTests {

    // MARK: - Visibility

    @Test("The card stays hidden until the server says this climber may connect")
    func hiddenUntilAvailable() async {
        let client = FakeStravaIntegrationClient(status: .hidden)
        let viewModel = StravaIntegrationViewModel(client: client, presenter: FakeStravaAuthorizationPresenter())

        #expect(viewModel.status.isVisible == false)
        await viewModel.refresh()
        #expect(viewModel.status.isVisible == false)

        client.status = StravaConnectionStatus(isAvailable: true, isConnected: false, athleteName: nil)
        await viewModel.refresh()
        #expect(viewModel.status.isVisible)
    }

    @Test("A connected climber keeps the card after the switch is turned off, so they can leave")
    func connectedStaysVisible() {
        let status = StravaConnectionStatus(isAvailable: false, isConnected: true, athleteName: "Elias M.")
        #expect(status.isVisible)
    }

    @Test("A failed status read keeps the card the climber was already shown")
    func failedRefreshKeepsLastStatus() async {
        let connected = StravaConnectionStatus(isAvailable: true, isConnected: true, athleteName: "Elias M.")
        let client = FakeStravaIntegrationClient(status: connected)
        let viewModel = StravaIntegrationViewModel(client: client, presenter: FakeStravaAuthorizationPresenter())
        await viewModel.refresh()

        client.fetchError = StravaIntegrationError.stravaUnreachable
        await viewModel.refresh()

        #expect(viewModel.status == connected)
        #expect(viewModel.statusLabel == "Connected · Elias M.")
    }

    // MARK: - Connecting

    @Test("An approved redirect is completed on the server with its code and state")
    func approvedConnectCompletes() async {
        let client = FakeStravaIntegrationClient(
            status: StravaConnectionStatus(isAvailable: true, isConnected: false, athleteName: nil)
        )
        client.completedStatus = StravaConnectionStatus(isAvailable: true, isConnected: true, athleteName: "Elias M.")
        let presenter = FakeStravaAuthorizationPresenter(
            callback: URL(string: "ascendapp://ascendstepper.com/strava?state=abc&code=xyz&scope=activity:write")
        )
        let viewModel = StravaIntegrationViewModel(client: client, presenter: presenter)

        await viewModel.connect()

        #expect(presenter.presented == [FakeStravaIntegrationClient.request])
        #expect(client.completions.count == 1)
        #expect(client.completions.first?.code == "xyz")
        #expect(client.completions.first?.state == "abc")
        #expect(viewModel.status.isConnected)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isWorking == false)
    }

    @Test("Cancelling Strava's sheet or tapping Cancel on its consent page is not an error")
    func cancelledConnectIsSilent() async {
        for callback in [nil, URL(string: "ascendapp://ascendstepper.com/strava?state=abc&error=access_denied")] {
            let client = FakeStravaIntegrationClient(
                status: StravaConnectionStatus(isAvailable: true, isConnected: false, athleteName: nil)
            )
            let viewModel = StravaIntegrationViewModel(
                client: client,
                presenter: FakeStravaAuthorizationPresenter(callback: callback)
            )

            await viewModel.connect()

            #expect(client.completions.isEmpty)
            #expect(viewModel.errorMessage == nil)
            #expect(viewModel.status.isConnected == false)
        }
    }

    @Test("A refused connect explains itself in Ascend's voice")
    func refusedConnectExplains() async {
        let client = FakeStravaIntegrationClient(
            status: StravaConnectionStatus(isAvailable: true, isConnected: false, athleteName: nil)
        )
        client.completeError = StravaIntegrationError.missingUploadPermission
        let viewModel = StravaIntegrationViewModel(
            client: client,
            presenter: FakeStravaAuthorizationPresenter(
                callback: URL(string: "ascendapp://ascendstepper.com/strava?state=abc&code=xyz&scope=read")
            )
        )

        await viewModel.connect()

        #expect(viewModel.errorMessage == "Ascend needs permission to upload your activities. Connect again and leave it ticked.")
    }

    @Test("A climber the server no longer allows is told, and the card refreshes away")
    func unavailableRefreshes() async {
        let client = FakeStravaIntegrationClient(
            status: StravaConnectionStatus(isAvailable: true, isConnected: false, athleteName: nil)
        )
        let viewModel = StravaIntegrationViewModel(client: client, presenter: FakeStravaAuthorizationPresenter())
        await viewModel.refresh()
        client.beginError = StravaIntegrationError.unavailable
        client.status = .hidden

        await viewModel.connect()

        #expect(viewModel.errorMessage == "Strava isn't open to your account yet.")
        #expect(viewModel.status.isVisible == false)
    }

    @Test("A redirect without a code is treated as an expired sign-in")
    func malformedRedirect() async {
        let client = FakeStravaIntegrationClient(
            status: StravaConnectionStatus(isAvailable: true, isConnected: false, athleteName: nil)
        )
        let viewModel = StravaIntegrationViewModel(
            client: client,
            presenter: FakeStravaAuthorizationPresenter(callback: URL(string: "ascendapp://ascendstepper.com/strava"))
        )

        await viewModel.connect()

        #expect(client.completions.isEmpty)
        #expect(viewModel.errorMessage == "That Strava sign-in expired. Connect again.")
    }

    // MARK: - Disconnecting

    @Test("Disconnecting reads back the server's status")
    func disconnect() async {
        let client = FakeStravaIntegrationClient(
            status: StravaConnectionStatus(isAvailable: true, isConnected: true, athleteName: "Elias M.")
        )
        client.disconnectedStatus = StravaConnectionStatus(isAvailable: true, isConnected: false, athleteName: nil)
        let viewModel = StravaIntegrationViewModel(client: client, presenter: FakeStravaAuthorizationPresenter())
        await viewModel.refresh()

        await viewModel.disconnect()

        #expect(client.disconnects == 1)
        #expect(viewModel.status.isConnected == false)
    }

    @Test("A failed disconnect keeps the connection on screen and says so")
    func failedDisconnect() async {
        let client = FakeStravaIntegrationClient(
            status: StravaConnectionStatus(isAvailable: true, isConnected: true, athleteName: "Elias M.")
        )
        client.disconnectError = StravaIntegrationError.stravaUnreachable
        let viewModel = StravaIntegrationViewModel(client: client, presenter: FakeStravaAuthorizationPresenter())
        await viewModel.refresh()

        await viewModel.disconnect()

        #expect(viewModel.status.isConnected)
        #expect(viewModel.errorMessage == "Couldn't disconnect Strava. Try again.")
    }

    // MARK: - Parsing

    @Test("The status payload fails closed")
    func statusPayloadFailsClosed() {
        #expect(StravaConnectionStatus(callablePayload: nil) == .hidden)
        #expect(StravaConnectionStatus(callablePayload: ["available": "yes"]) == .hidden)
        #expect(
            StravaConnectionStatus(callablePayload: ["available": true, "connected": true, "athleteName": "  "])
                == StravaConnectionStatus(isAvailable: true, isConnected: true, athleteName: nil)
        )
    }

    @Test("Strava's redirect is read for its code, state and denial")
    func callbackParsing() {
        #expect(
            StravaAuthorizationCallback(url: URL(string: "ascendapp://x/strava?state=s&code=c&scope=activity:write")!)
                == .approved(code: "c", state: "s")
        )
        #expect(StravaAuthorizationCallback(url: URL(string: "ascendapp://x/strava?state=s&error=access_denied")!) == .denied)
        #expect(StravaAuthorizationCallback(url: URL(string: "ascendapp://x/strava?code=c")!) == .invalid)
    }

    @Test("Callable refusals map to their reasons")
    func callableErrorMapping() {
        func error(reason: String?) -> NSError {
            var userInfo: [String: Any] = [:]
            if let reason {
                userInfo[FunctionsErrorDetailsKey] = ["reason": reason]
            }
            return NSError(domain: FunctionsErrorDomain, code: 9, userInfo: userInfo)
        }
        #expect(FunctionsStravaIntegrationClient.integrationError(for: error(reason: "unavailable")) == .unavailable)
        #expect(FunctionsStravaIntegrationClient.integrationError(for: error(reason: "expired")) == .authorizationExpired)
        #expect(FunctionsStravaIntegrationClient.integrationError(for: error(reason: "missing_scope")) == .missingUploadPermission)
        if case .other = FunctionsStravaIntegrationClient.integrationError(for: error(reason: nil)) {} else {
            Issue.record("an unknown refusal must map to .other")
        }
    }
}
