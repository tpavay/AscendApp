import Foundation

enum GzipCodec {
    enum Error: LocalizedError {
        case compressionFailed

        var errorDescription: String? {
            switch self {
            case .compressionFailed:
                return "Failed to compress the heart-rate series."
            }
        }
    }

    static func compress(_ data: Data) throws -> Data {
        guard let compressedNSData = try (data as NSData).compressed(using: .zlib) as Data?,
              compressedNSData.count >= 6 else {
            throw Error.compressionFailed
        }

        let deflatePayload = compressedNSData.dropFirst(2).dropLast(4)
        var gzipData = Data([
            0x1f, 0x8b, // magic
            0x08,       // deflate
            0x00,       // flags
            0x00, 0x00, 0x00, 0x00, // mtime
            0x00,       // extra flags
            0xff        // OS unknown
        ])
        gzipData.append(deflatePayload)

        var crc32 = Self.crc32(for: data).littleEndian
        withUnsafeBytes(of: &crc32) { gzipData.append(contentsOf: $0) }

        var inputSize = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &inputSize) { gzipData.append(contentsOf: $0) }

        return gzipData
    }
}

private extension GzipCodec {
    static func crc32(for data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff

        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = crcTable[index] ^ (crc >> 8)
        }

        return crc ^ 0xffff_ffff
    }

    static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if (crc & 1) == 1 {
                crc = 0xedb8_8320 ^ (crc >> 1)
            } else {
                crc = crc >> 1
            }
        }
        return crc
    }
}
