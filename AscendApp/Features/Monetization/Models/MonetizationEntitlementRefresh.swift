import Foundation

/// What a refresh actually established, as opposed to what the stored entitlement happens to say.
///
/// A purchase verdict is only as truthful as the answer behind it. Returning the stored state alone
/// cannot distinguish "RevenueCat says this climber has nothing" from "nobody could ask", so a
/// transitional `.unknown` would read as a lapsed subscription for someone who was just charged.
enum MonetizationEntitlementRefresh: Equatable, Sendable {
    /// RevenueCat answered for this refresh, so the state is current.
    case refreshed(MonetizationEntitlementState)
    /// No current answer could be established, so nothing here describes the climber's access.
    case unavailable(MonetizationEntitlementRefreshFailure)
}

enum MonetizationEntitlementRefreshFailure: Equatable, Sendable {
    /// The build has no RevenueCat to ask.
    case notConfigured
    /// An identity mutation never resolved, so there is no settled identity to ask about.
    case identityUnresolved
    /// RevenueCat was asked and did not answer.
    case providerFailed
}
