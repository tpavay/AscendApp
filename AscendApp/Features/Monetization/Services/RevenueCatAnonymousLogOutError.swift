import Foundation
import RevenueCat

/// RevenueCat refuses to log out an app user that is already anonymous, which is the state of every
/// fresh install and every signed-out cold start. That refusal is a confirmed "nobody is signed in",
/// not a failure to answer, so it must resolve the identity mutation instead of leaving it pending.
enum RevenueCatAnonymousLogOutError {
    static let domain = ErrorCode.errorDomain
    static let code = ErrorCode.logOutAnonymousUserError.rawValue

    static func matches(_ error: any Error) -> Bool {
        if let errorCode = error as? ErrorCode {
            return errorCode == .logOutAnonymousUserError
        }

        let nsError = error as NSError
        return nsError.domain == domain && nsError.code == code
    }
}
