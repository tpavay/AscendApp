import Foundation

/// A single heart-rate reading from a connected monitor.
struct HeartRateMeasurement: Equatable, Sendable {
    enum SensorContact: Equatable, Sendable {
        /// The device does not report sensor-contact state.
        case unsupported
        /// The device reports the sensor is not against skin (reading may be junk).
        case notDetected
        case detected
    }

    let beatsPerMinute: Int
    let sensorContact: SensorContact
    let receivedAt: Date
}

/// Parses the standard BLE Heart Rate Measurement characteristic (GATT 0x2A37).
///
/// Byte layout per the Bluetooth Heart Rate Service specification:
/// - Byte 0 is a flags field:
///   - bit 0: heart-rate value format (0 = UInt8, 1 = UInt16 little-endian)
///   - bits 1-2: sensor contact (bit 2 = feature supported, bit 1 = contact detected)
///   - bit 3: energy-expended field present (UInt16, skipped)
///   - bit 4: RR-interval values present (trailing UInt16s, unused)
/// - Heart-rate value follows the flags byte in the declared format.
enum HeartRateMeasurementParser {
    static func parse(_ data: Data, receivedAt: Date = Date()) -> HeartRateMeasurement? {
        guard data.count >= 2 else { return nil }

        let bytes = [UInt8](data)
        let flags = bytes[0]
        let isSixteenBit = flags & 0b0000_0001 != 0

        let beatsPerMinute: Int
        if isSixteenBit {
            guard bytes.count >= 3 else { return nil }
            beatsPerMinute = Int(bytes[1]) | (Int(bytes[2]) << 8)
        } else {
            beatsPerMinute = Int(bytes[1])
        }

        guard beatsPerMinute > 0 else { return nil }

        let sensorContact: HeartRateMeasurement.SensorContact
        if flags & 0b0000_0100 != 0 {
            sensorContact = flags & 0b0000_0010 != 0 ? .detected : .notDetected
        } else {
            sensorContact = .unsupported
        }

        return HeartRateMeasurement(
            beatsPerMinute: beatsPerMinute,
            sensorContact: sensorContact,
            receivedAt: receivedAt
        )
    }
}
