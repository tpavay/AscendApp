import Foundation

/// One attempt of a server-preferred read that did not return the server's answer.
struct ServerReadFailure: Sendable {
    let error: any Error
    let failureClass: ServerReadFailureClass

    init(_ error: any Error) {
        self.error = error
        self.failureClass = ServerReadFailureClass.classify(error)
    }
}
