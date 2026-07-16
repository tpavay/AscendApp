import Foundation

protocol ClimbImageRepository: Sendable {
    func resolveImageURL(for climb: Climb, variant: ClimbImageVariant) async -> URL?
}
