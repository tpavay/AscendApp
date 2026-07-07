@preconcurrency import FirebaseAuth
import Foundation

/// Resolves the signed-in climber's zone profile from their declared age.
/// Falls back to the age-agnostic default when signed out, the profile has
/// no age yet, or the fetch fails — zones are display-only, so a fallback
/// band is always acceptable.
enum HeartRateZoneProfileResolver {
    static func resolve() async -> HeartRateZoneProfile {
        guard let userId = Auth.auth().currentUser?.uid else {
            return HeartRateZoneProfile(age: nil)
        }

        let userData = try? await UserDataRepository.shared.getUserFromFirestore(userId: userId)
        return HeartRateZoneProfile(age: userData?.age)
    }
}
