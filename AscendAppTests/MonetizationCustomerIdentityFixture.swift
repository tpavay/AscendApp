@testable import AscendApp

extension MonetizationCustomerIdentity {
    /// A climber identified by account id alone, for the tests whose subject is the identity
    /// transition itself rather than what reaches the RevenueCat customer record.
    static func climber(_ userID: String) -> MonetizationCustomerIdentity {
        MonetizationCustomerIdentity(userID: userID)
    }
}
