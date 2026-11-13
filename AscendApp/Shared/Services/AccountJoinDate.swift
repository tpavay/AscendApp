import FirebaseAuth
import FirebaseCore
import Foundation

/// When the signed-in climber's account was created, from Firebase Auth.
///
/// The one clock "every climb after you sign up counts" is measured against, because it is
/// the clock the server ranks on: `functions/src/leaderboardStats.ts` reads the same creation time
/// from Auth. A date the climber could edit - a profile field, the device clock - would let the
/// phone and the board disagree about which climbs are history.
enum AccountJoinDate {
    /// Nil when nobody is signed in or Firebase is not configured, as in a test process that never
    /// started it. Callers treat nil as "cannot judge" and leave the verdict to the server.
    static func current() -> Date? {
        guard FirebaseApp.app() != nil else { return nil }
        return Auth.auth().currentUser?.metadata.creationDate
    }
}
