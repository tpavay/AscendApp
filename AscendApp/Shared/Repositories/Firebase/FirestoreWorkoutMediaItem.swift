import Foundation

struct FirestoreWorkoutMediaItem: Codable, Equatable, Sendable {
    let id: String
    let url: String
    let uploadedAt: Date
    let type: String
    let durationSeconds: Double?

    init(
        id: String,
        url: String,
        uploadedAt: Date,
        type: String,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.url = url
        self.uploadedAt = uploadedAt
        self.type = type
        self.durationSeconds = durationSeconds
    }
}
