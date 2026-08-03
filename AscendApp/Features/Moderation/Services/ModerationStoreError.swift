import Foundation

enum ModerationStoreError: LocalizedError {
    case invalidAccount

    var errorDescription: String? {
        "Your account changed. Try again."
    }
}
