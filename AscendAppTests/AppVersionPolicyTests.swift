import Foundation
import Testing
@testable import AscendApp

struct AppVersionPolicyTests {
    @Test("Numeric components are compared semantically", .bug(id: 319))
    func numericComponentsUseSemanticOrdering() throws {
        let older = try #require(SemanticAppVersion("1.9.0"))
        let newer = try #require(SemanticAppVersion("1.10.0"))

        #expect(older < newer)
    }

    @Test("Missing trailing components compare as zero", .bug(id: 319))
    func missingTrailingComponentsCompareAsZero() throws {
        let short = try #require(SemanticAppVersion("1.0"))
        let explicit = try #require(SemanticAppVersion("1.0.0"))

        #expect(short == explicit)
    }

    @Test(
        "Malformed semantic versions are rejected",
        .bug(id: 319),
        arguments: [
            "", " ", " 1.0.0", "1.0.0 ", ".1.0", "1..0", "1.0.", "1.0.0.0",
            "1.a.0", "v1.0.0", "1.0-beta", "01.0.0", "1.-1.0"
        ]
    )
    func malformedVersionsAreRejected(rawValue: String) {
        #expect(SemanticAppVersion(rawValue) == nil)
    }

    @Test("A missing version is rejected", .bug(id: 319))
    func missingVersionIsRejected() {
        #expect(SemanticAppVersion(nil) == nil)
    }

    @Test("A current version below minimum requires an update", .bug(id: 319))
    func belowMinimumRequiresUpdate() {
        let result = AppVersionPolicy.evaluate(
            currentVersion: "1.0",
            minimumSupportedVersion: "1.0.1",
            recommendedVersion: "1.2.0"
        )

        #expect(result == .required)
    }

    @Test("A version below only the recommendation may defer", .bug(id: 319))
    func belowOnlyRecommendedSuggestsUpdate() {
        let result = AppVersionPolicy.evaluate(
            currentVersion: "1.1.0",
            minimumSupportedVersion: "1.0.0",
            recommendedVersion: "1.2.0"
        )

        #expect(result == .recommended)
    }

    @Test(
        "Versions at or above both thresholds continue",
        .bug(id: 319),
        arguments: ["1.2.0", "1.2.1", "2.0.0"]
    )
    func currentVersionsContinue(currentVersion: String) {
        let result = AppVersionPolicy.evaluate(
            currentVersion: currentVersion,
            minimumSupportedVersion: "1.0.0",
            recommendedVersion: "1.2.0"
        )

        #expect(result == nil)
    }

    @Test(
        "Any malformed input fails open",
        .bug(id: 319),
        arguments: [
            ("", "1.0.0", "1.1.0"),
            ("1.0", "", "1.1.0"),
            ("1.0", "1.0.0", ""),
            ("1.0", "not-a-version", "1.1.0"),
            ("1.0", "1.0.0", "1.1.0-beta")
        ]
    )
    func malformedInputsFailOpen(
        currentVersion: String,
        minimumVersion: String,
        recommendedVersion: String
    ) {
        let result = AppVersionPolicy.evaluate(
            currentVersion: currentVersion,
            minimumSupportedVersion: minimumVersion,
            recommendedVersion: recommendedVersion
        )

        #expect(result == nil)
    }

    @Test("Missing inputs fail open", .bug(id: 319))
    func missingInputsFailOpen() {
        #expect(AppVersionPolicy.evaluate(
            currentVersion: nil,
            minimumSupportedVersion: "1.0.0",
            recommendedVersion: "1.1.0"
        ) == nil)
        #expect(AppVersionPolicy.evaluate(
            currentVersion: "1.0",
            minimumSupportedVersion: nil,
            recommendedVersion: "1.1.0"
        ) == nil)
        #expect(AppVersionPolicy.evaluate(
            currentVersion: "1.0",
            minimumSupportedVersion: "1.0.0",
            recommendedVersion: nil
        ) == nil)
    }

    @Test("The checked-in zero thresholds are inert", .bug(id: 319))
    func zeroThresholdsAreInert() {
        let result = AppVersionPolicy.evaluate(
            currentVersion: "1.0",
            minimumSupportedVersion: "0.0.0",
            recommendedVersion: "0.0.0"
        )

        #expect(result == nil)
    }

    @Test("The production provider reads the app marketing version", .bug(id: 319))
    func productionProviderReadsPinnedMarketingVersion() {
        #expect(AppMarketingVersionProvider.mainBundle.currentVersion() == "1.0")
    }

    @Test("The marketing version provider is injectable", .bug(id: 319))
    func marketingVersionProviderIsInjectable() {
        let provider = AppMarketingVersionProvider { "7.4.2" }

        #expect(provider.currentVersion() == "7.4.2")
    }

    @Test("The update CTA meets enhanced text contrast", .bug(id: 319))
    func updateCTAUsesAccessibleContrast() {
        let ratio = contrastRatio(
            AppUpdateButtonColors.foregroundSRGB,
            AppUpdateButtonColors.backgroundSRGB
        )

        #expect(ratio >= 7)
    }

    private func contrastRatio(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double {
        let brighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (brighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: SIMD3<Double>) -> Double {
        func linearize(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return (0.2126 * linearize(color.x))
            + (0.7152 * linearize(color.y))
            + (0.0722 * linearize(color.z))
    }
}

@MainActor
struct AppVersionGateStateTests {
    @Test("Only a recommended prompt can be dismissed with Later", .bug(id: 319))
    func laterOnlyDismissesRecommendedPrompt() {
        let required = AppVersionGateState(presentation: .required)
        required.dismissRecommended()
        #expect(required.presentation == .required)

        let recommended = AppVersionGateState(presentation: .recommended)
        recommended.dismissRecommended()
        #expect(recommended.presentation == nil)
    }

    @Test("Presentation capabilities match the required and recommended contract", .bug(id: 319))
    func presentationCapabilitiesMatchContract() {
        #expect(AppUpdatePresentation.required.allowsInteractiveDismissal == false)
        #expect(AppUpdatePresentation.required.showsLaterAction == false)
        #expect(AppUpdatePresentation.recommended.allowsInteractiveDismissal)
        #expect(AppUpdatePresentation.recommended.showsLaterAction)
    }

    @Test("The App Store destination uses Ascend's production product", .bug(id: 319))
    func appStoreDestinationUsesProductionProduct() {
        #expect(AscendAppStoreDestination.productID == "6757202987")
        #expect(AscendAppStoreDestination.productURL?.absoluteString == "https://apps.apple.com/app/id6757202987")
    }
}
