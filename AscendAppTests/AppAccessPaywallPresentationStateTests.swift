import Testing
@testable import AscendApp

@MainActor
struct AppAccessPaywallPresentationStateTests {
    @Test
    func gatePhaseIsTheOnlyPresentationSourceOfTruth() {
        #expect(AppAccessGatePhase.allCases == [
            .openingHosted,
            .hostedPresented,
            .loadingNative,
            .nativeReady,
            .purchasing,
            .verifying,
            .verificationUnavailable,
            .pendingApproval,
            .accessConfirmed,
            .failed,
            .backUnavailable
        ])
    }

    @Test(arguments: [
        AppAccessGatePhase.openingHosted,
        .hostedPresented,
        .loadingNative,
        .purchasing,
        .verifying,
        .verificationUnavailable,
        .pendingApproval,
        .accessConfirmed,
        .backUnavailable
    ])
    func nonPurchaseReadyPhasesCannotEnablePurchase(phase: AppAccessGatePhase) {
        let coordinator = makeCoordinator(initialPhase: phase)

        #expect(coordinator.disablesPurchase)
        #expect(coordinator.showsPurchaseControls == false)
    }

    private func makeCoordinator(initialPhase: AppAccessGatePhase) -> AppAccessPaywallCoordinator {
        AppAccessPaywallCoordinator(
            monetizationManager: MonetizationManager(
                entitlementService: EntitlementServiceStub(),
                paywallPresenter: PaywallPresenterSpy(),
                telemetry: makeTestTelemetry(
                    sink: InMemoryTelemetrySink(destination: .analytics)
                )
            ),
            initialPhase: initialPhase
        )
    }
}
