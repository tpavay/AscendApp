@preconcurrency import FirebaseFirestore
import Foundation

/// What the signed-out city screen knows about a city's climbers.
enum CityClimberCount: Equatable, Sendable {
    /// The published count, which is zero for a city the server has no document for.
    case climbers(Int)
    /// The count could not be established: the read failed, or the server has never published.
    /// The screen then says nothing about this city's climbers rather than guessing zero.
    case unknown
}

protocol CityClimberCountReading: Sendable {
    func count(for selection: PostAuthLocationSelection) async -> CityClimberCount
}

/// Reads `public_city_climber_counts/{key}` and the run's `_summary`, which rules let a signed-out
/// phone fetch one document at a time. Without a summary a missing city document proves nothing -
/// the server may never have run - so only a summary makes an absent document mean zero.
struct FirestoreCityClimberCountReader: CityClimberCountReading {
    static let collection = "public_city_climber_counts"
    static let summaryID = "_summary"

    func count(for selection: PostAuthLocationSelection) async -> CityClimberCount {
        guard let key = CityClimberCountKey.key(for: selection) else { return .unknown }

        let counts = Firestore.firestore().collection(Self.collection)
        do {
            async let city = counts.document(key).getServerDocument()
            async let summary = counts.document(Self.summaryID).getServerDocument()
            let (cityDocument, summaryDocument) = try await (city, summary)

            guard summaryDocument.exists else { return .unknown }
            guard cityDocument.exists else { return .climbers(0) }
            guard let climbers = (cityDocument.data()?["climbers"] as? NSNumber)?.intValue, climbers >= 0 else {
                return .unknown
            }
            return .climbers(climbers)
        } catch {
            return .unknown
        }
    }
}
