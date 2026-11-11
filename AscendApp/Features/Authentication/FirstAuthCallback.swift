/// What Firebase's first auth-state callback of this process reported, beside what the app already
/// held when it arrived. The synchronous `Auth.auth().currentUser` read at launch can see nobody for
/// a climber who is still signed in, so only this callback settles who is.
struct FirstAuthCallback: Equatable, Sendable {
    /// The callback carried a user.
    let reportedUser: Bool
    /// A user was already restored in this process before the callback arrived.
    let followedRestoredUser: Bool

    /// Nobody was signed in at launch, as far as Firebase could tell.
    var reportsNobodySignedIn: Bool { !reportedUser && !followedRestoredUser }
}
