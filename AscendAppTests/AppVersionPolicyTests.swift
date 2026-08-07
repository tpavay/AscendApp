import Foundation
import SwiftUI
import Testing
import UIKit
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
        "A malformed current version fails the whole evaluation open",
        .bug(id: 319),
        arguments: ["", " ", "not-a-version", "1.0.0-beta", "v1.0"]
    )
    func malformedCurrentVersionFailsOpen(currentVersion: String) {
        let result = AppVersionPolicy.evaluate(
            currentVersion: currentVersion,
            minimumSupportedVersion: "1.1.0",
            recommendedVersion: "1.2.0"
        )

        #expect(result == nil)
    }

    @Test(
        "A malformed minimum fails open on its own terms only",
        .bug(id: 319),
        arguments: ["", " ", "not-a-version", "1.1.0-beta"]
    )
    func malformedMinimumLeavesTheRecommendationIntact(minimumVersion: String) {
        #expect(AppVersionPolicy.evaluate(
            currentVersion: "1.0",
            minimumSupportedVersion: minimumVersion,
            recommendedVersion: "1.2.0"
        ) == .recommended)
        #expect(AppVersionPolicy.evaluate(
            currentVersion: "1.0",
            minimumSupportedVersion: minimumVersion,
            recommendedVersion: "1.0.0"
        ) == nil)
    }

    /// The lockout must not depend on the lower-stakes value: a captain who arms the minimum
    /// mid-incident and leaves the recommendation empty or typo'd still locks the fleet out.
    @Test(
        "A malformed recommendation cannot veto the required lockout",
        .bug(id: 319),
        arguments: ["", " ", "not-a-version", "1.2.0-beta"]
    )
    func malformedRecommendationCannotVetoTheLockout(recommendedVersion: String) {
        let result = AppVersionPolicy.evaluate(
            currentVersion: "1.0",
            minimumSupportedVersion: "1.1.0",
            recommendedVersion: recommendedVersion
        )

        #expect(result == .required)
    }

    @Test("Missing inputs fail open on their own terms", .bug(id: 319))
    func missingInputsFailOpenIndependently() {
        #expect(AppVersionPolicy.evaluate(
            currentVersion: nil,
            minimumSupportedVersion: "1.0.0",
            recommendedVersion: "1.1.0"
        ) == nil)
        #expect(AppVersionPolicy.evaluate(
            currentVersion: "1.0",
            minimumSupportedVersion: nil,
            recommendedVersion: "1.1.0"
        ) == .recommended)
        #expect(AppVersionPolicy.evaluate(
            currentVersion: "1.0",
            minimumSupportedVersion: "1.1.0",
            recommendedVersion: nil
        ) == .required)
        #expect(AppVersionPolicy.evaluate(
            currentVersion: "1.0",
            minimumSupportedVersion: nil,
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

    @Test("The production provider reads a version the policy can compare", .bug(id: 319))
    func productionProviderReadsAParseableMarketingVersion() throws {
        let currentVersion = try #require(AppMarketingVersionProvider.mainBundle.currentVersion())

        _ = try #require(SemanticAppVersion(currentVersion))
    }

    @Test("The marketing version provider is injectable", .bug(id: 319))
    func marketingVersionProviderIsInjectable() {
        let provider = AppMarketingVersionProvider { "7.4.2" }

        #expect(provider.currentVersion() == "7.4.2")
    }

    /// Measured off the resolved colours the button actually renders, not off copied literals, so
    /// editing the AccentColor asset moves this assertion instead of leaving it measuring a ghost.
    @MainActor
    @Test("The update CTA meets enhanced text contrast", .bug(id: 319))
    func updateCTAUsesAccessibleContrast() throws {
        let ratio = contrastRatio(
            try sRGBComponents(of: AppSheetAccentContrastColors.foreground),
            try sRGBComponents(of: AppSheetAccentContrastColors.background)
        )

        #expect(ratio >= 7)
    }

    /// The sheet renders on `AppSheetPalette`'s black regardless of the system setting, so the dark
    /// resolution is the one on screen.
    @MainActor
    private func sRGBComponents(of color: Color) throws -> SIMD3<Double> {
        let resolved = UIColor(color)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        try #require(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))

        return SIMD3(Double(red), Double(green), Double(blue))
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

    /// Backgrounding into aeroplane mode and foregrounding again is a failed fetch, not evidence
    /// that this build became supported. Clearing here made the lockout a one-tap bypass.
    @Test("A failed fetch cannot repeal an armed required lockout", .bug(id: 319))
    func failingOpenCannotRepealTheRequiredLockout() {
        let required = AppVersionGateState(presentation: .required)
        required.failOpen()
        #expect(required.presentation == .required)

        let recommended = AppVersionGateState(presentation: .recommended)
        recommended.failOpen()
        #expect(recommended.presentation == nil)

        let unresolved = AppVersionGateState()
        unresolved.failOpen()
        #expect(unresolved.presentation == nil)
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
