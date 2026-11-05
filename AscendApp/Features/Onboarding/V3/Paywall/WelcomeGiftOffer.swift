import Foundation

/// The welcome gift as the store describes it: the discounted yearly plan beside the regular one.
///
/// Every number comes from StoreKit through the two plans. The percentage is computed, never typed,
/// and rounds down so the stamp never claims more than the store charges.
struct WelcomeGiftOffer: Equatable, Sendable {
    let price: String
    let regularPrice: String
    /// Whole percent off the regular yearly price, or `nil` when either price is unknown or the gift
    /// is not cheaper.
    let percentOff: Int?
    /// The free period the Apple ID can still take, read from the offer itself. `nil` when the
    /// product carries none or the Apple ID already used its trial - then no copy promises one.
    let freeTrial: FreeTrial?

    struct FreeTrial: Equatable, Sendable {
        /// "7 days", as the store's period reads once a single week is spelled out.
        let duration: String
        /// Whether the period is exactly seven days, which is when "first week" is the true name.
        let isOneWeek: Bool
    }

    init?(welcome: NativePaywallPlan, regular: NativePaywallPlan) {
        guard welcome.billing == .subscription else { return nil }

        price = welcome.localizedPrice
        regularPrice = regular.localizedPrice
        percentOff = Self.percentOff(regular: regular.price, welcome: welcome.price)
        freeTrial = Self.freeTrial(from: welcome.freeTrialPeriod)
    }

    static func percentOff(regular: Decimal?, welcome: Decimal?) -> Int? {
        guard let regular, let welcome, regular > 0, welcome >= 0, welcome < regular else { return nil }

        let fraction = (regular - welcome) / regular * 100
        var rounded = Decimal()
        var source = fraction
        NSDecimalRound(&rounded, &source, 0, .down)
        let percent = NSDecimalNumber(decimal: rounded).intValue
        return percent > 0 ? percent : nil
    }

    private static func freeTrial(from period: NativeSubscriptionPeriod?) -> FreeTrial? {
        guard let period else { return nil }

        let days: Int? = switch period.unit {
        case .day: period.value
        case .week: period.value * 7
        case .month, .year, .unknown: nil
        }

        if let days {
            return FreeTrial(
                duration: days == 1 ? "1 day" : "\(days) days",
                isOneWeek: days == 7
            )
        }

        let unit: String? = switch period.unit {
        case .month: period.value == 1 ? "month" : "months"
        case .year: period.value == 1 ? "year" : "years"
        case .day, .week, .unknown: nil
        }
        guard let unit else { return nil }

        return FreeTrial(duration: "\(period.value) \(unit)", isOneWeek: false)
    }
}

/// The words on the gift, written from the offer so an Apple ID that can no longer take the trial
/// never reads a line promising one.
struct WelcomeGiftCopy: Equatable, Sendable {
    /// "PLUS 7 DAYS FREE", or `nil` when there is no trial to name.
    let trialLine: String?
    let headlineLead: [String]
    let headlineAccent: [String]
    let subline: String
    let callToAction: String
    let finePrint: String
    let stamp: String?

    init(_ offer: WelcomeGiftOffer) {
        stamp = offer.percentOff.map { "\($0)%" }

        if let trial = offer.freeTrial {
            let span = trial.isOneWeek ? "week" : trial.duration
            trialLine = "Plus \(trial.duration) free".uppercased()
            headlineLead = ["Your first \(span)"]
            headlineAccent = ["is on us."]
            subline = "Then \(offer.price) a year, locked in."
            callToAction = "Claim my gift"
            finePrint = "Free today, then \(offer.price)/year. Cancel anytime."
        } else {
            trialLine = nil
            headlineLead = ["\(offer.price) a year,"]
            headlineAccent = ["locked in."]
            subline = offer.percentOff.map { "That's \($0)% off, every year you climb." }
                ?? "Every year you climb."
            callToAction = "Claim my gift"
            finePrint = "\(offer.price) today, then every year. Cancel anytime."
        }
    }
}
