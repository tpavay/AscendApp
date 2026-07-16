import Foundation

enum ProfileViewMode: Equatable {
    case own
    case otherUser

    var showsActivationEmptyStates: Bool {
        self == .own
    }
}
