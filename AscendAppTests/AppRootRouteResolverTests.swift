import Foundation
import Testing
@testable import AscendApp

struct AppRootRouteResolverTests {
    @Test
    func resolvesSignedOutWhenThereIsNoAuthenticatedUser() {
        let route = AppRootRouteResolver.resolve(
            authenticationState: .authenticated,
            userId: nil,
            postAuthOnboardingPhase: .complete,
            entitlementState: .active(["app_access"]),
            requiredEntitlementID: "app_access"
        )

        #expect(route == .signedOut)
    }

    @Test
    func resolvesSigningInBeforeUserIsAvailable() {
        let route = AppRootRouteResolver.resolve(
            authenticationState: .authenticatingWithApple,
            userId: nil,
            postAuthOnboardingPhase: .signedOut,
            entitlementState: .unknown,
            requiredEntitlementID: "app_access"
        )

        #expect(route == .signingIn)
    }

    @Test
    func resolvesOnboardingBeforeCheckingAccess() {
        let route = AppRootRouteResolver.resolve(
            authenticationState: .authenticated,
            userId: "user-1",
            postAuthOnboardingPhase: .onboarding(.displayName),
            entitlementState: .inactive,
            requiredEntitlementID: "app_access"
        )

        #expect(route == .onboarding(.displayName))
    }

    @Test
    func resolvesPaywallWhenOnboardingIsCompleteWithoutAccess() {
        let route = AppRootRouteResolver.resolve(
            authenticationState: .authenticated,
            userId: "user-1",
            postAuthOnboardingPhase: .complete,
            entitlementState: .inactive,
            requiredEntitlementID: "app_access"
        )

        #expect(route == .paywall)
    }

    @Test
    func resolvesMainAppWhenUnentitledAccessIsAllowed() {
        let route = AppRootRouteResolver.resolve(
            authenticationState: .authenticated,
            userId: "user-1",
            postAuthOnboardingPhase: .complete,
            entitlementState: .inactive,
            requiredEntitlementID: "app_access",
            allowsUnentitledAppAccess: true
        )

        #expect(route == .mainApp)
    }

    @Test
    func resolvesMainAppWhenOnboardingIsCompleteWithAccess() {
        let route = AppRootRouteResolver.resolve(
            authenticationState: .authenticated,
            userId: "user-1",
            postAuthOnboardingPhase: .complete,
            entitlementState: .active(["app_access"]),
            requiredEntitlementID: "app_access"
        )

        #expect(route == .mainApp)
    }

    @Test
    func resolvesWhileAccessStateIsUnknown() {
        let route = AppRootRouteResolver.resolve(
            authenticationState: .authenticated,
            userId: "user-1",
            postAuthOnboardingPhase: .complete,
            entitlementState: .unknown,
            requiredEntitlementID: "app_access"
        )

        #expect(route == .resolving)
    }

    @Test
    func resolvesMainAppWhenUnentitledAccessIsAllowedBeforeAccessStateLoads() {
        let route = AppRootRouteResolver.resolve(
            authenticationState: .authenticated,
            userId: "user-1",
            postAuthOnboardingPhase: .complete,
            entitlementState: .unknown,
            requiredEntitlementID: "app_access",
            allowsUnentitledAppAccess: true
        )

        #expect(route == .mainApp)
    }
}
