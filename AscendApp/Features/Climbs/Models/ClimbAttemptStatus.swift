import Foundation

enum ClimbAttemptStatus: String, Codable {
    case active
    case completed
    case failed
    case abandoned
}
