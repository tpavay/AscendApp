import Foundation
import Testing
@testable import AscendApp

/// A completed sign-out or deletion is its own event, so a request that never lands reads as the
/// gap between the tap and this.
@MainActor
struct AccountExitAnalyticsTests {
    @Test
    func theTwoExitsNameTheScreenTheyCameFrom() {
        let out = AccountExitAnalyticsEvent.signedOut(surface: .appAccessGate).record
        #expect(out.name == "account_signed_out")
        #expect(out.parameters["surface"] == .string("app_access_gate"))

        let deleted = AccountExitAnalyticsEvent.deleted(surface: .appAccessGate).record
        #expect(deleted.name == "account_deleted")
        #expect(deleted.parameters["surface"] == .string("app_access_gate"))
    }

    @Test
    func everySurfaceIsABoundedId() {
        let ids = [
            AccountExitSurface.appAccessGate, .appAccessResolving, .updateRequired,
            .accountDataConflict, .settings, .onboarding
        ].map(\.rawValue)

        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.range(of: #"^[a-z_]+$"#, options: .regularExpression) != nil })
    }
}
