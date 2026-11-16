import FirebaseAuth
import Foundation

/// What a failed sign-in actually was, decided from the error the provider returned and never
/// from the fact that a sign-in failed.
///
/// One sentence used to stand for every failure - "Unable to sign in. Please check your
/// connection and try again." - so App Review read a failure of Apple's own authorization on a
/// device with a working connection as the app not recognising the internet (Guideline 2.1(a),
/// 1.3.0 build 2026111401). The sentence a climber reads has to match the failure, so the kind
/// is a fact about the error and the copy follows from it.
enum AuthenticationFailureKind: String, Equatable, Sendable {
    /// The phone could not reach a server: no route, a dropped or timed-out connection, data
    /// switched off. The only kind whose message may talk about the connection.
    case connectivity
    /// Apple's own authorization controller failed before any Ascend request was made - the
    /// sheet could not complete on this device. The climber's way on is the other provider.
    case appleAuthorization
    /// Anything else a provider or Firebase answered with: a refused credential, a disabled
    /// account, a server fault. Reachable, so never described as a connection problem.
    case providerRejected
}

/// The error a sign-in failed with, kept as plain values: its kind, and the domains and codes
/// that explain it.
///
/// Domain and code are the only way to tell these failures apart afterwards. Apple's controller
/// reports nearly every refusal as one `ASAuthorizationError` and the app used to discard both,
/// so Sentry held one bucket (`ASCEND-IOS-1F`) for what were several different causes. They are
/// an OS error domain and an integer, never a message, so they carry no personal data.
struct AuthenticationFailureDiagnostics: Equatable, Sendable {
    let kind: AuthenticationFailureKind
    let errorDomain: String
    let errorCode: Int
    let underlyingDomain: String?
    let underlyingCode: Int?
    /// The provider's own wording, for logs only. It is never shown to a climber.
    let detail: String

    /// How deep an underlying-error chain is followed. Firebase wraps a transport error once and
    /// Google wraps Firebase's, so three levels reach every real cause without trusting a cycle.
    private static let underlyingDepthLimit = 4

    /// Transport failures that mean the phone, not the service, is the problem. A bad server
    /// response, a TLS failure and a cancelled request are deliberately absent: the connection
    /// worked, or the request was ours to cancel.
    private static let connectivityCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorDataNotAllowed,
        NSURLErrorInternationalRoamingOff,
        NSURLErrorCallIsActive
    ]

    init(
        kind: AuthenticationFailureKind,
        errorDomain: String,
        errorCode: Int,
        underlyingDomain: String? = nil,
        underlyingCode: Int? = nil,
        detail: String = ""
    ) {
        self.kind = kind
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.underlyingDomain = underlyingDomain
        self.underlyingCode = underlyingCode
        self.detail = detail
    }

    /// Classifies a failure from the error alone. Anything in the error's chain that is a
    /// connectivity failure makes the whole failure one - the system sheet and Firebase both
    /// need the network, and either wraps the transport error that says so. Otherwise the
    /// provider answered, and the failure is `otherwise`: `appleAuthorization` for Apple's
    /// controller, `providerRejected` for Firebase and Google.
    init(error: Error, otherwise: AuthenticationFailureKind) {
        let nsError = error as NSError
        let isConnectivity = Self.chain(of: nsError).contains(where: Self.isConnectivityFailure)
        let underlying = Self.firstUnderlying(of: nsError)

        self.init(
            kind: isConnectivity ? .connectivity : otherwise,
            errorDomain: nsError.domain,
            errorCode: nsError.code,
            underlyingDomain: underlying?.domain,
            underlyingCode: underlying?.code,
            detail: error.localizedDescription
        )
    }

    /// The small, stable tag set recorded beside a failed sign-in.
    var telemetryInfo: [String: String] {
        var info = [
            "failure_kind": kind.rawValue,
            "error_domain": errorDomain,
            "error_code": String(errorCode)
        ]
        if let underlyingDomain { info["underlying_domain"] = underlyingDomain }
        if let underlyingCode { info["underlying_code"] = String(underlyingCode) }
        return info
    }

    private static func chain(of error: NSError) -> [NSError] {
        var chain = [error]
        var current = error
        while chain.count < underlyingDepthLimit,
              let next = current.userInfo[NSUnderlyingErrorKey] as? NSError {
            chain.append(next)
            current = next
        }
        return chain
    }

    private static func firstUnderlying(of error: NSError) -> NSError? {
        error.userInfo[NSUnderlyingErrorKey] as? NSError
    }

    private static func isConnectivityFailure(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain {
            return connectivityCodes.contains(error.code)
        }
        // Firebase reports its own transport failure as one code in its own domain.
        return error.domain == AuthErrorDomain && error.code == AuthErrorCode.networkError.rawValue
    }
}
