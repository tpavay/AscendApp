import Foundation
import Testing
@testable import AscendApp

struct HeartRateMeasurementParserTests {
    @Test
    func parsesEightBitHeartRate() throws {
        let measurement = try #require(HeartRateMeasurementParser.parse(Data([0b0000_0000, 72])))
        #expect(measurement.beatsPerMinute == 72)
        #expect(measurement.sensorContact == .unsupported)
    }

    @Test
    func parsesSixteenBitHeartRateLittleEndian() throws {
        // 0x0110 = 272 bpm — implausible but exercises the wide format.
        let measurement = try #require(HeartRateMeasurementParser.parse(Data([0b0000_0001, 0x10, 0x01])))
        #expect(measurement.beatsPerMinute == 272)
    }

    @Test
    func parsesSensorContactStates() throws {
        let detected = try #require(HeartRateMeasurementParser.parse(Data([0b0000_0110, 140])))
        #expect(detected.sensorContact == .detected)

        let notDetected = try #require(HeartRateMeasurementParser.parse(Data([0b0000_0100, 140])))
        #expect(notDetected.sensorContact == .notDetected)
    }

    @Test
    func parsesValueWithEnergyExpendedAndRRIntervals() throws {
        // Flags: 8-bit HR + contact supported/detected + energy expended + RR present.
        let data = Data([0b0001_1110, 155, 0x34, 0x12, 0x00, 0x04, 0x10, 0x04])
        let measurement = try #require(HeartRateMeasurementParser.parse(data))
        #expect(measurement.beatsPerMinute == 155)
        #expect(measurement.sensorContact == .detected)
    }

    @Test
    func rejectsMalformedPackets() {
        #expect(HeartRateMeasurementParser.parse(Data()) == nil)
        #expect(HeartRateMeasurementParser.parse(Data([0b0000_0000])) == nil)
        // 16-bit flag but only one value byte present.
        #expect(HeartRateMeasurementParser.parse(Data([0b0000_0001, 72])) == nil)
        // Zero bpm is not a usable reading.
        #expect(HeartRateMeasurementParser.parse(Data([0b0000_0000, 0])) == nil)
    }
}

struct HeartRateZoneTests {
    @Test
    func tanakaMaxHeartRateFromAge() {
        // 208 − 0.7 × 30 = 187
        #expect(HeartRateZoneProfile(age: 30).maxHeartRate == 187)
        // 208 − 0.7 × 50 = 173
        #expect(HeartRateZoneProfile(age: 50).maxHeartRate == 173)
    }

    @Test
    func missingAgeUsesFallback() {
        #expect(HeartRateZoneProfile(age: nil) == HeartRateZoneProfile(age: HeartRateZoneProfile.fallbackAge))
    }

    @Test
    func implausibleAgesAreBounded() {
        #expect(HeartRateZoneProfile(age: 5).maxHeartRate == HeartRateZoneProfile(age: 13).maxHeartRate)
        #expect(HeartRateZoneProfile(age: 500).maxHeartRate == HeartRateZoneProfile(age: 120).maxHeartRate)
    }

    @Test
    func zoneBoundariesSplitAtSeventyAndEightyFivePercent() {
        let profile = HeartRateZoneProfile(age: 30) // max 187
        let recoveryCeiling = Int(Double(profile.maxHeartRate) * HeartRateZoneProfile.recoveryUpperFraction)
        let aerobicCeiling = Int(Double(profile.maxHeartRate) * HeartRateZoneProfile.aerobicUpperFraction)

        #expect(profile.zone(forBeatsPerMinute: 60) == .recovery)
        #expect(profile.zone(forBeatsPerMinute: recoveryCeiling - 1) == .recovery)
        #expect(profile.zone(forBeatsPerMinute: recoveryCeiling + 1) == .aerobic)
        #expect(profile.zone(forBeatsPerMinute: aerobicCeiling - 1) == .aerobic)
        #expect(profile.zone(forBeatsPerMinute: aerobicCeiling + 1) == .push)
        #expect(profile.zone(forBeatsPerMinute: profile.maxHeartRate + 20) == .push)
    }
}
