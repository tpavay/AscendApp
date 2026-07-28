import Foundation

struct FirestoreWorkoutHeartRateSeriesReference: Codable, Equatable, Sendable {
    static let defaultEncoding = "json+gzip"

    let storagePath: String
    let encoding: String
    let sampleCount: Int
    let seriesStartAt: Date
    let seriesEndAt: Date
    let objectSchemaVersion: Int?
    let compressedByteCount: Int?
    let sha256: String?

    init(
        storagePath: String,
        encoding: String = FirestoreWorkoutHeartRateSeriesReference.defaultEncoding,
        sampleCount: Int,
        seriesStartAt: Date,
        seriesEndAt: Date,
        objectSchemaVersion: Int? = nil,
        compressedByteCount: Int? = nil,
        sha256: String? = nil
    ) {
        self.storagePath = storagePath
        self.encoding = encoding
        self.sampleCount = sampleCount
        self.seriesStartAt = seriesStartAt
        self.seriesEndAt = seriesEndAt
        self.objectSchemaVersion = objectSchemaVersion
        self.compressedByteCount = compressedByteCount
        self.sha256 = sha256
    }
}
