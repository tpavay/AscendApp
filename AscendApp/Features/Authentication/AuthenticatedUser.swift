import Foundation
@preconcurrency import FirebaseAuth

struct AuthenticatedUser: Equatable, Sendable {
    let uid: String
    let email: String?
    let photoURL: URL?
    let creationDate: Date?

    init(
        uid: String,
        email: String?,
        photoURL: URL?,
        creationDate: Date?
    ) {
        self.uid = uid
        self.email = email
        self.photoURL = photoURL
        self.creationDate = creationDate
    }

    init(firebaseUser: User) {
        self.init(
            uid: firebaseUser.uid,
            email: firebaseUser.email,
            photoURL: firebaseUser.photoURL,
            creationDate: firebaseUser.metadata.creationDate
        )
    }
}
