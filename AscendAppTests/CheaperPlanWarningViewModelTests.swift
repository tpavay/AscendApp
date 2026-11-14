import Foundation
import Testing
@testable import AscendApp

/// What the two buttons, the tap and the switch do. The rule under all of it: cancelling is
/// never blocked, hidden or delayed.
@MainActor
struct CheaperPlanWarningViewModelTests {
    private final class StubProvider: SubscriberRateProviding {
        var snapshot: SubscriberRateSnapshot?
        private(set) var readCount = 0

        init(_ snapshot: SubscriberRateSnapshot?) {
            self.snapshot = snapshot
        }

        func currentRates() async -> SubscriberRateSnapshot? {
            readCount += 1
            return snapshot
        }
    }

    private final class EventLog {
        var records: [TelemetryRecord] = []
        var names: [String] { records.map(\.name) }
    }

    private static func rate(_ id: String, _ price: Decimal, formatted: String) -> SubscriptionRate {
        SubscriptionRate(
            productID: id,
            price: price,
            currencyCode: "USD",
            period: .year,
            formattedPrice: formatted
        )
    }

    private static let welcomeSnapshot = SubscriberRateSnapshot(
        held: .subscription(
            rate: rate("ascend_yearly_welcome", 9.99, formatted: "$9.99"),
            isInFreeTrial: false,
            willAutoRenew: true
        ),
        standardYearly: rate("ascend_yearly", 29.99, formatted: "$29.99")
    )

    private static let standardSnapshot = SubscriberRateSnapshot(
        held: .subscription(
            rate: rate("ascend_yearly", 29.99, formatted: "$29.99"),
            isInFreeTrial: false,
            willAutoRenew: true
        ),
        standardYearly: rate("ascend_yearly", 29.99, formatted: "$29.99")
    )

    private func makeModel(
        snapshot: SubscriberRateSnapshot?,
        isEnabled: Bool = true
    ) -> (CheaperPlanWarningViewModel, StubProvider, EventLog) {
        let provider = StubProvider(snapshot)
        let log = EventLog()
        let model = CheaperPlanWarningViewModel(
            provider: provider,
            featureFlags: RemoteFeatureFlagStore(
                snapshot: .resolving(remoteValues: [
                    RemoteFeatureFlag.cheaperPlanCancelWarning.key: isEnabled
                ])
            ),
            track: { log.records.append($0.record) }
        )
        return (model, provider, log)
    }

    // MARK: - The tap

    @Test
    func tappingManageWithACheaperPlanShowsTheWarningAndNotAppleYet() async {
        let (model, _, log) = makeModel(snapshot: Self.welcomeSnapshot)
        await model.refresh()
        var opened = 0

        model.manageTapped { opened += 1 }

        #expect(model.isPresentingWarning)
        #expect(opened == 0)
        #expect(log.names == ["cheaper_plan_warning_shown"])
    }

    @Test
    func tappingManageOnTheStandardPlanOpensAppleAtOnce() async {
        let (model, _, log) = makeModel(snapshot: Self.standardSnapshot)
        await model.refresh()
        var opened = 0

        model.manageTapped { opened += 1 }

        #expect(!model.isPresentingWarning)
        #expect(opened == 1)
        #expect(log.names.isEmpty)
    }

    @Test
    func tappingManageBeforeTheStoreHasAnsweredOpensAppleAtOnce() {
        let (model, _, log) = makeModel(snapshot: Self.welcomeSnapshot)
        var opened = 0

        model.manageTapped { opened += 1 }

        #expect(!model.isPresentingWarning)
        #expect(opened == 1)
        #expect(log.names.isEmpty)
    }

    @Test
    func aStoreThatCouldNotAnswerNeverBlocksCancelling() async {
        let (model, _, _) = makeModel(snapshot: nil)
        await model.refresh()
        var opened = 0

        model.manageTapped { opened += 1 }

        #expect(opened == 1)
        #expect(!model.isPresentingWarning)
    }

    // MARK: - The buttons

    @Test
    func keepMyPlanDismissesAndDoesNotOpenAppleOrCancelAnything() async {
        let (model, _, log) = makeModel(snapshot: Self.welcomeSnapshot)
        await model.refresh()
        var opened = 0
        model.manageTapped { opened += 1 }

        model.keepTapped()

        #expect(!model.isPresentingWarning)
        #expect(opened == 0)
        #expect(log.names == ["cheaper_plan_warning_shown", "cheaper_plan_warning_keep_tapped"])
    }

    @Test
    func continueToCancelDismissesAndOpensApplesCancellationFlow() async {
        let (model, _, log) = makeModel(snapshot: Self.welcomeSnapshot)
        await model.refresh()
        var opened = 0
        model.manageTapped { opened += 1 }

        model.continueTapped { opened += 1 }

        #expect(!model.isPresentingWarning)
        #expect(opened == 1)
        #expect(log.names == ["cheaper_plan_warning_shown", "cheaper_plan_warning_continue_tapped"])
    }

    @Test
    func continueToCancelStillOpensAppleWhenNoWarningIsHeld() {
        let (model, _, log) = makeModel(snapshot: nil)
        var opened = 0

        model.continueTapped { opened += 1 }

        #expect(opened == 1)
        #expect(log.names.isEmpty)
    }

    // MARK: - The switch

    @Test
    func withTheSwitchOffManageOpensAppleAtOnceAndTheStoreIsNeverRead() async {
        let (model, provider, log) = makeModel(snapshot: Self.welcomeSnapshot, isEnabled: false)
        await model.refresh()
        var opened = 0

        model.manageTapped { opened += 1 }

        #expect(opened == 1)
        #expect(!model.isPresentingWarning)
        #expect(provider.readCount == 0)
        #expect(log.names.isEmpty)
    }

    @Test
    func aSwitchTurnedOffAfterTheReadStillOpensAppleAtOnce() async {
        let provider = StubProvider(Self.welcomeSnapshot)
        let store = RemoteFeatureFlagStore(
            snapshot: .resolving(remoteValues: [RemoteFeatureFlag.cheaperPlanCancelWarning.key: true])
        )
        let model = CheaperPlanWarningViewModel(provider: provider, featureFlags: store, track: { _ in })
        await model.refresh()
        _ = store.apply(.resolving(remoteValues: [RemoteFeatureFlag.cheaperPlanCancelWarning.key: false]))
        var opened = 0

        model.manageTapped { opened += 1 }

        #expect(opened == 1)
        #expect(!model.isPresentingWarning)
    }

    @Test
    func theSwitchShipsOn() {
        #expect(RemoteFeatureFlag.cheaperPlanCancelWarning.shippedDefault)
        #expect(!RemoteFeatureFlag.cheaperPlanCancelWarning.isRollout)
    }

    // MARK: - A failed read keeps what the last good one said

    @Test
    func aLaterFailedReadDoesNotTakeAnEarlierWarningAway() async {
        let (model, provider, _) = makeModel(snapshot: Self.welcomeSnapshot)
        await model.refresh()
        provider.snapshot = nil

        await model.refresh()

        #expect(model.warning != nil)
    }

    // MARK: - Apple's sheet closing

    private static let cancelledWelcomeSnapshot = SubscriberRateSnapshot(
        held: .subscription(
            rate: rate("ascend_yearly_welcome", 9.99, formatted: "$9.99"),
            isInFreeTrial: false,
            willAutoRenew: false
        ),
        standardYearly: rate("ascend_yearly", 29.99, formatted: "$29.99")
    )

    @Test
    func aClimberWhoCancelledInApplesSheetIsNotWarnedAgainAfterItCloses() async {
        let (model, provider, log) = makeModel(snapshot: Self.welcomeSnapshot)
        await model.refresh()
        var opened = 0
        model.manageTapped { opened += 1 }
        model.continueTapped { opened += 1 }
        provider.snapshot = Self.cancelledWelcomeSnapshot

        await model.systemFlowClosed()
        model.manageTapped { opened += 1 }

        #expect(provider.readCount == 2)
        #expect(!model.isPresentingWarning)
        #expect(opened == 2)
        #expect(log.names == ["cheaper_plan_warning_shown", "cheaper_plan_warning_continue_tapped"])
    }

    @Test
    func aReadThatFailsAfterApplesSheetClosesDoesNotBringTheOldWarningBack() async {
        let (model, provider, log) = makeModel(snapshot: Self.welcomeSnapshot)
        await model.refresh()
        model.manageTapped { }
        model.continueTapped { }
        provider.snapshot = nil

        await model.systemFlowClosed()
        var opened = 0
        model.manageTapped { opened += 1 }

        #expect(model.warning == nil)
        #expect(opened == 1)
        #expect(log.names == ["cheaper_plan_warning_shown", "cheaper_plan_warning_continue_tapped"])
    }

    @Test
    func aClimberWhoKeptTheirPlanInApplesSheetIsWarnedAgainAfterItCloses() async {
        let (model, provider, _) = makeModel(snapshot: Self.welcomeSnapshot)
        await model.refresh()
        model.manageTapped { }
        model.continueTapped { }

        await model.systemFlowClosed()
        var opened = 0
        model.manageTapped { opened += 1 }

        #expect(provider.readCount == 2)
        #expect(model.isPresentingWarning)
        #expect(opened == 0)
    }

    // MARK: - Analytics properties

    @Test
    func everyEventCarriesTheRateAndThePercentageCheaper() async throws {
        let (model, _, log) = makeModel(snapshot: Self.welcomeSnapshot)
        await model.refresh()
        model.manageTapped { }
        model.keepTapped()
        model.manageTapped { }
        model.continueTapped { }

        #expect(log.names == [
            "cheaper_plan_warning_shown",
            "cheaper_plan_warning_keep_tapped",
            "cheaper_plan_warning_shown",
            "cheaper_plan_warning_continue_tapped"
        ])
        for record in log.records {
            #expect(record.parameters["percent_cheaper"] == .int(67))
            #expect(record.parameters["rate"] == .double(9.99))
            #expect(record.parameters["standard_rate"] == .double(29.99))
            #expect(record.parameters["currency"] == .string("USD"))
            #expect(record.parameters["period"] == .string("year"))
            #expect(record.parameters["product_id"] == .string("ascend_yearly_welcome"))
            #expect(record.parameters["is_free_trial"] == .bool(false))
        }
    }
}
