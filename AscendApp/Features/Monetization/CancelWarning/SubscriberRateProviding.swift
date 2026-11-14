import Foundation
import RevenueCat
import StoreKit

/// What the warning needs from the store: the plan the climber holds and what the standard yearly
/// plan costs today. Both are read live, never remembered, because both move without a release.
struct SubscriberRateSnapshot: Equatable, Sendable {
    let held: HeldPlan?
    let standardYearly: SubscriptionRate?
}

@MainActor
protocol SubscriberRateProviding: AnyObject {
    /// `nil` when the store could not answer. That is never a reason to warn.
    func currentRates() async -> SubscriberRateSnapshot?
}

/// Reads the held plan from RevenueCat and prices it, and the standard yearly plan, from StoreKit.
///
/// RevenueCat says *which* product pays for `app_access`, whether it is a trial, and whether it
/// renews. StoreKit says what that product costs this climber: `renewalPrice` is the price their
/// next renewal bills at, which is what a grandfathered subscriber still pays after the product's
/// list price moved, and what a climber inside a trial will be charged when it ends. Neither is
/// hardcoded.
@MainActor
final class StoreKitSubscriberRateProvider: SubscriberRateProviding {
    private let configuration: MonetizationConfiguration

    init(configuration: MonetizationConfiguration = .live) {
        self.configuration = configuration
    }

    func currentRates() async -> SubscriberRateSnapshot? {
        guard Purchases.isConfigured else { return nil }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            guard let entitlement = customerInfo.entitlements.activeInAnyEnvironment[
                configuration.revenueCatEntitlementID
            ] else {
                // Free week, no plan, or lapsed: nothing here can be cancelled.
                return SubscriberRateSnapshot(held: nil, standardYearly: nil)
            }

            guard entitlement.store == .appStore else {
                return SubscriberRateSnapshot(held: nil, standardYearly: nil)
            }

            if entitlement.productIdentifier == configuration.revenueCatLifetimeProductID
                || entitlement.expirationDate == nil {
                return SubscriberRateSnapshot(held: .lifetime, standardYearly: nil)
            }

            let products = try await Product.products(
                for: [entitlement.productIdentifier, configuration.revenueCatYearlyProductID]
            )
            guard let heldProduct = products.first(where: { $0.id == entitlement.productIdentifier }),
                  heldProduct.type == .autoRenewable else { return nil }

            let held = await heldPlan(
                product: heldProduct,
                isInFreeTrial: entitlement.periodType == .trial,
                revenueCatWillRenew: entitlement.willRenew
            )
            let standard = products
                .first(where: { $0.id == configuration.revenueCatYearlyProductID })
                .flatMap { Self.listRate(for: $0) }

            return SubscriberRateSnapshot(held: held, standardYearly: standard)
        } catch {
            return nil
        }
    }

    private func heldPlan(
        product: Product,
        isInFreeTrial: Bool,
        revenueCatWillRenew: Bool
    ) async -> HeldPlan? {
        guard let period = product.subscription.flatMap({ Self.ratePeriod($0.subscriptionPeriod) }) else {
            return nil
        }

        let renewal = await Self.renewalInfo(for: product)
        let price = renewal?.renewalPrice ?? product.price
        let currencyCode = renewal?.currency?.identifier ?? product.priceFormatStyle.currencyCode
        let rate = SubscriptionRate(
            productID: product.id,
            price: price,
            currencyCode: currencyCode,
            period: period,
            formattedPrice: SubscriptionRatePriceFormatter.string(
                price: price,
                currencyCode: currencyCode,
                locale: product.priceFormatStyle.locale
            )
        )

        return .subscription(
            rate: rate,
            isInFreeTrial: isInFreeTrial,
            willAutoRenew: renewal?.willAutoRenew ?? revenueCatWillRenew
        )
    }

    private static func listRate(for product: Product) -> SubscriptionRate? {
        guard let period = product.subscription.flatMap({ ratePeriod($0.subscriptionPeriod) }) else {
            return nil
        }

        return SubscriptionRate(
            productID: product.id,
            price: product.price,
            currencyCode: product.priceFormatStyle.currencyCode,
            period: period,
            formattedPrice: product.displayPrice
        )
    }

    private static func renewalInfo(for product: Product) async -> Product.SubscriptionInfo.RenewalInfo? {
        guard let statuses = try? await product.subscription?.status else { return nil }

        let live: Set<Product.SubscriptionInfo.RenewalState> = [
            .subscribed, .inGracePeriod, .inBillingRetryPeriod
        ]
        for status in statuses where live.contains(status.state) {
            guard case .verified(let info) = status.renewalInfo,
                  info.currentProductID == product.id else { continue }
            return info
        }
        return nil
    }

    private static func ratePeriod(_ period: Product.SubscriptionPeriod) -> RatePeriod? {
        let unit: RatePeriod.Unit
        switch period.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: return nil
        }
        return RatePeriod(unit: unit, value: period.value)
    }
}
