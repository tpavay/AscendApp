import Foundation
import Testing
@testable import AscendApp

@MainActor
struct AscendURLSchemeTests {
    @Test("This build answers to the scheme its configuration names, never a shared one")
    func theBuildCarriesItsOwnScheme() {
        let registered = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        #expect(registered.contains(AscendURLScheme.current))
        #expect(registered.filter { $0.hasPrefix(AscendURLScheme.production) } == [AscendURLScheme.current],
                "a second Ascend scheme would let another installed build answer this one's links")
        let expected = switch Bundle.main.bundleIdentifier {
        case "com.TylerPavay.AscendApp.dev": "ascendapp-dev"
        case "com.TylerPavay.AscendApp.staging": "ascendapp-stg"
        default: AscendURLScheme.production
        }
        #expect(AscendURLScheme.current == expected)
    }

    @Test("A bundle without the key, or with it unexpanded, falls back to the App Store scheme")
    func fallsBackToProduction() {
        #expect(AscendURLScheme.resolved(from: nil) == "ascendapp")
        #expect(AscendURLScheme.resolved(from: "") == "ascendapp")
        #expect(AscendURLScheme.resolved(from: "$(ASCEND_URL_SCHEME)") == "ascendapp")
        #expect(AscendURLScheme.resolved(from: "ascendapp-stg") == "ascendapp-stg")
    }

    @Test("A Live Activity link opens the build that started the climb")
    func liveActivityLinkRoundTrips() throws {
        let attributes = LiveClimbActivityAttributes(
            sessionID: "session-1",
            climbID: "burj-khalifa",
            climbName: "Burj Khalifa",
            climbLocation: "Dubai",
            targetSteps: 2_909
        )
        let url = try #require(attributes.deepLinkURL)

        #expect(url.scheme == AscendURLScheme.current)
        #expect(LiveClimbActivityRouter.shared.route(from: url))
        #expect(LiveClimbActivityRouter.shared.consumePendingRoute() == LiveClimbActivityRoute(sessionID: "session-1", climbID: "burj-khalifa"))
    }
}
