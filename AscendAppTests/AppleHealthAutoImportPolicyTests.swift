import Foundation
import Testing
@testable import AscendApp

struct AppleHealthAutoImportPolicyTests {
    @Test
    func ignoresManualImportCandidatesBeforeActivationDate() {
        let activatedAt = Date(timeIntervalSince1970: 1_775_400_000)
        let sample = HealthKitWorkoutSample(
            externalRecordID: "ah_old",
            startDate: Date(timeIntervalSince1970: 1_775_390_000),
            endDate: Date(timeIntervalSince1970: 1_775_391_800),
            duration: 1_800,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            deviceModel: "Apple Watch"
        )

        let policy = AppleHealthAutoImportPolicy(activatedAt: activatedAt)

        #expect(policy.shouldAutoImport(.appleHealth(sample: sample)) == false)
    }

    @Test
    func autoImportsAppleHealthCandidatesEndingAfterActivationDate() {
        let activatedAt = Date(timeIntervalSince1970: 1_775_400_000)
        let sample = HealthKitWorkoutSample(
            externalRecordID: "ah_new",
            startDate: Date(timeIntervalSince1970: 1_775_399_400),
            endDate: Date(timeIntervalSince1970: 1_775_401_200),
            duration: 1_800,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            deviceModel: "Apple Watch"
        )

        let policy = AppleHealthAutoImportPolicy(activatedAt: activatedAt)

        #expect(policy.shouldAutoImport(.appleHealth(sample: sample)))
    }

    @Test
    func usesFallbackActivationDateWhenStoredActivationDateIsMissing() {
        let fallbackActivatedAt = Date(timeIntervalSince1970: 1_775_400_000)
        let sample = HealthKitWorkoutSample(
            externalRecordID: "ah_fallback_new",
            startDate: Date(timeIntervalSince1970: 1_775_400_300),
            endDate: Date(timeIntervalSince1970: 1_775_402_100),
            duration: 1_800,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            deviceModel: "Apple Watch"
        )

        let policy = AppleHealthAutoImportPolicy(
            activatedAt: nil,
            missingActivationFallback: fallbackActivatedAt
        )

        #expect(policy.shouldAutoImport(.appleHealth(sample: sample)))
    }

    @Test
    func ignoresFallbackCandidatesBeforeFallbackActivationDate() {
        let fallbackActivatedAt = Date(timeIntervalSince1970: 1_775_400_000)
        let sample = HealthKitWorkoutSample(
            externalRecordID: "ah_fallback_old",
            startDate: Date(timeIntervalSince1970: 1_775_397_000),
            endDate: Date(timeIntervalSince1970: 1_775_398_800),
            duration: 1_800,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            deviceModel: "Apple Watch"
        )

        let policy = AppleHealthAutoImportPolicy(
            activatedAt: nil,
            missingActivationFallback: fallbackActivatedAt
        )

        #expect(policy.shouldAutoImport(.appleHealth(sample: sample)) == false)
    }

}
