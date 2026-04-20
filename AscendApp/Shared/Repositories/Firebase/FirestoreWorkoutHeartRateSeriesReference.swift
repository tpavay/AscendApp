import Foundation

struct FirestoreWorkoutHeartRateSeriesReference: Codable, Equatable, Sendable {
    static let defaultEncoding = "json+gzip"

    let storagePath: String
    let encoding: String
    let sampleCount: Int
    let seriesStartAt: Date
    let seriesEndAt: Date

    init(
        storagePath: String,
        encoding: String = FirestoreWorkoutHeartRateSeriesReference.defaultEncoding,
        sampleCount: Int,
        seriesStartAt: Date,
        seriesEndAt: Date
    ) {
        self.storagePath = storagePath
        self.encoding = encoding
        self.sampleCount = sampleCount
        self.seriesStartAt = seriesStartAt
        self.seriesEndAt = seriesEndAt
    }
}
