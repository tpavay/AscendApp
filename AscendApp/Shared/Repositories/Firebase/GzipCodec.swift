import Foundation

enum GzipCodec {
    enum Error: LocalizedError {
        case compressionFailed
        case invalidGzipData
        case decompressionFailed

        var errorDescription: String? {
            switch self {
            case .compressionFailed:
                return "Failed to compress the heart-rate series."
            case .invalidGzipData:
                return "The heart-rate series is not valid gzip data."
            case .decompressionFailed:
                return "Failed to decompress the heart-rate series."
            }
        }
    }

    static func compress(_ data: Data) throws -> Data {
        guard let compressedNSData = try (data as NSData).compressed(using: .zlib) as Data?,
              !compressedNSData.isEmpty else {
            throw Error.compressionFailed
        }

        var gzipData = Data([
            0x1f, 0x8b, // magic
            0x08,       // deflate
            0x00,       // flags
            0x00, 0x00, 0x00, 0x00, // mtime
            0x00,       // extra flags
            0xff        // OS unknown
        ])
        gzipData.append(compressedNSData)

        var crc32 = Self.crc32(for: data).littleEndian
        withUnsafeBytes(of: &crc32) { gzipData.append(contentsOf: $0) }

        var inputSize = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &inputSize) { gzipData.append(contentsOf: $0) }

        return gzipData
    }

    static func decompress(_ data: Data) throws -> Data {
        guard data.count >= 18,
              data[0] == 0x1f,
              data[1] == 0x8b,
              data[2] == 0x08,
              data[3] == 0x00 else {
            throw Error.invalidGzipData
        }

        let compressedPayload = data.dropFirst(10).dropLast(8)
        do {
            return try (Data(compressedPayload) as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw Error.decompressionFailed
        }
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
