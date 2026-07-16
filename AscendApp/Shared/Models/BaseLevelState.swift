import Foundation

enum BaseLevelState: String, Codable, Sendable {
    case seeded
    case autoCalculated
    case manualOverride
}
