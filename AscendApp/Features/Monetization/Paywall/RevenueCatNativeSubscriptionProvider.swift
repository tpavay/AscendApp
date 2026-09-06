import Foundation
import RevenueCat
import SuperwallKit

enum RevenueCatNativeSubscriptionProviderError: LocalizedError, Equatable {
    case notConfigured

    var errorDescription: String? {
        "Subscription options are unavailable right now. Try again in a moment."
    }
}

@MainActor
final class RevenueCatNativeSubscriptionProvider: NativeSubscriptionProviding {
    private let configuration: MonetizationConfiguration
    private let coordinator: @MainActor () -> any PaywallPurchaseCoordinating
    private let executor: RevenueCatPurchaseExecutor
    private let isPurchasesConfigured: @MainActor () -> Bool
    private var purchaseTargetsByProductID: [String: PurchaseTarget] = [:]

    init(
        configuration: MonetizationConfiguration = .live,
        coordinator: @escaping @MainActor () -> any PaywallPurchaseCoordinating = {
            MonetizationManager.shared
        },
        isPurchasesConfigured: @escaping @MainActor () -> Bool = { Purchases.isConfigured }
    ) {
        self.configuration = configuration
        self.coordinator = coordinator
        self.isPurchasesConfigured = isPurchasesConfigured
        executor = RevenueCatPurchaseExecutor(
            entitlementID: configuration.revenueCatEntitlementID,
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: {
                await coordinator().refreshEntitlements(
                    force: true,
                    waitsForPendingIdentity: true
                )
            },
            currentIdentityGeneration: {
                coordinator().identityGeneration
            },
            adoptEntitlementState: { state, identity in
                coordinator().adoptPurchaseEntitlementState(state, for: identity)
            }
        )
    }

    func loadPlans() async throws -> [NativeSubscriptionPlan] {
        guard isPurchasesConfigured() else {
            throw RevenueCatNativeSubscriptionProviderError.notConfigured
        }
        let expectedProductIDs = Set(configuration.launchProductIDs)
        let offerings = try? await Purchases.shared.offerings()
        let offering = offerings?.all[configuration.revenueCatOfferingID]
            ?? offerings?.current
        let packages = (offering?.availablePackages ?? []).filter {
            expectedProductIDs.contains($0.storeProduct.productIdentifier)
        }
        var targets = Dictionary(
            uniqueKeysWithValues: packages.map {
                ($0.storeProduct.productIdentifier, PurchaseTarget.package($0))
            }
        )
        let missingProductIDs = configuration.launchProductIDs.filter { targets[$0] == nil }
        let directProducts = await Purchases.shared.products(missingProductIDs)
        for product in directProducts where expectedProductIDs.contains(product.productIdentifier) {
            targets[product.productIdentifier] = .product(product)
        }
        purchaseTargetsByProductID = targets

        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: Array(targets.keys)
        )

        let productTerms = targets.values.map {
            Self.productTerms(from: $0.storeProduct)
        }
        let eligibilityByProductID = Dictionary(
            uniqueKeysWithValues: targets.keys.map { productID in
                let trialEligibility: NativeTrialEligibility
                if let providerEligibility = eligibility[productID] {
                    trialEligibility = providerEligibility.status.isEligible
                        ? .eligible
                        : .ineligible
                } else {
                    trialEligibility = .unknown
                }
                return (productID, trialEligibility)
            }
        )

        return NativeSubscriptionPlanMapper.plans(
            from: productTerms,
            eligibilityByProductID: eligibilityByProductID,
            yearlyProductID: configuration.revenueCatYearlyProductID,
            monthlyProductID: configuration.revenueCatMonthlyProductID
        )
    }

    func purchase(planID: String) async -> PurchaseResult {
        guard isPurchasesConfigured() else {
            return executor.failPurchaseBeforeRevenueCatCall(
                productID: planID,
                error: RevenueCatNativeSubscriptionProviderError.notConfigured,
                errorType: .configuration
            )
        }
        guard let purchaseTarget = purchaseTargetsByProductID[planID] else {
            return executor.failPurchaseBeforeRevenueCatCall(
                productID: planID,
                error: RevenueCatPurchaseControllerError.missingStoreKitProduct,
                errorType: .missingStoreProduct
            )
        }

        return await executor.executePurchase(productID: planID) {
            let result: PurchaseResultData
            switch purchaseTarget {
            case .package(let package):
                result = try await Purchases.shared.purchase(package: package)
            case .product(let product):
                result = try await Purchases.shared.purchase(product: product)
            }
            return RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: result.userCancelled,
                entitlementState: RevenueCatPurchasesProvider.entitlementState(
                    from: result.customerInfo
                )
            )
        }
    }

    private static func productTerms(
        from product: RevenueCat.StoreProduct
    ) -> NativeSubscriptionProductTerms {
        let freeTrialPeriod = product.introductoryDiscount.flatMap { discount in
            discount.paymentMode == .freeTrial
                ? nativePeriod(from: discount.subscriptionPeriod)
                : nil
        }

        return NativeSubscriptionProductTerms(
            productID: product.productIdentifier,
            localizedPrice: product.localizedPriceString,
            renewalPeriod: product.subscriptionPeriod.map(nativePeriod(from:)),
            freeTrialPeriod: freeTrialPeriod
        )
    }

    private static func nativePeriod(
        from period: RevenueCat.SubscriptionPeriod
    ) -> NativeSubscriptionPeriod {
        let unit: NativeSubscriptionPeriod.Unit = switch period.unit {
        case .day:
            .day
        case .week:
            .week
        case .month:
            .month
        case .year:
            .year
        @unknown default:
            .unknown
        }
        return NativeSubscriptionPeriod(value: period.value, unit: unit)
    }

    private enum PurchaseTarget {
        case package(Package)
        case product(RevenueCat.StoreProduct)

        var storeProduct: RevenueCat.StoreProduct {
            switch self {
            case .package(let package):
                package.storeProduct
            case .product(let product):
                product
            }
        }
    }
}
