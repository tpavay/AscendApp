import AuthenticationServices
import Foundation
import UIKit

/// What Apple's sheet handed back, as plain values.
///
/// `ASAuthorization` cannot be built outside the system, so everything downstream of the sheet reads
/// this instead: the exchange with Firebase, the identity capture, and the tests that stand in for
/// the sheet.
struct AppleAuthorizationCredential {
    let userID: String
    let identityToken: Data?
    let authorizationCode: Data?
    let fullName: PersonNameComponents?
    let email: String?

    init(
        userID: String,
        identityToken: Data?,
        authorizationCode: Data?,
        fullName: PersonNameComponents?,
        email: String?
    ) {
        self.userID = userID
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.fullName = fullName
        self.email = email
    }

    init(_ credential: ASAuthorizationAppleIDCredential) {
        self.init(
            userID: credential.user,
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode,
            fullName: credential.fullName,
            email: credential.email
        )
    }

    /// Apple supplies the name and email on the first authorization for an Apple ID and app pair
    /// and never again, so this is what gets recorded before anything else can fail.
    var suppliedIdentity: SignInSuppliedIdentity {
        SignInSuppliedIdentity(
            providerUserID: userID,
            firstName: fullName?.givenName,
            lastName: fullName?.familyName,
            email: email
        )
    }
}

/// What the attempt looked like from the app's side, recorded beside every Apple failure.
///
/// Apple's error alone cannot tell the two failures in production apart: a refusal that never showed
/// a sheet (Apple's own test fleet, 0 s) and a sheet that opened and then ended in an error (retail
/// phones, 1 to 12 s) arrive as the same `ASAuthorizationError`. These four facts do.
struct AppleAuthorizationTrace: Equatable, Sendable {
    /// The app lost the foreground between the request and its result - the system took the screen,
    /// which is what raising Apple's sheet does. `false` on a refusal that came back with no UI.
    let sheetPresented: Bool
    let millisecondsToResult: Int
    /// `UIScene.ActivationState` of the scene the sheet was anchored to, when the result arrived.
    let sceneState: String
    /// `UIApplication.State` when the result arrived.
    let applicationState: String
    /// How many Apple requests this process has made, this one included.
    let attemptNumber: Int
}

extension AppleAuthorizationTrace {
    var analyticsParameters: [String: TelemetryValue] {
        [
            "sheet_presented": .bool(sheetPresented),
            "ms_to_result": .int(millisecondsToResult),
            "scene_state": .string(sceneState),
            "app_state": .string(applicationState),
            "attempt_number": .int(attemptNumber)
        ]
    }
}

struct AppleAuthorizationOutcome {
    let result: Result<AppleAuthorizationCredential, Error>
    let trace: AppleAuthorizationTrace
}

enum AppleAuthorizationError: Error, Equatable {
    /// A second request arrived while one was still waiting on Apple. The first is left alone.
    case alreadyInProgress
}

/// The one thing the sign-in code asks of Authentication Services: raise the sheet for this request
/// and say what happened. Never returns twice, never returns for a request it did not start.
@MainActor
protocol AppleAuthorizationPerforming: AnyObject {
    func perform(_ request: ASAuthorizationAppleIDRequest) async -> AppleAuthorizationOutcome
}

/// Owns an Apple authorization from the moment it is requested to the moment it resolves.
///
/// Three things went wrong with this living inside `AuthenticationService` as loose state, and
/// each is an invariant here:
/// - **The controller is retained** for the whole request. It used to be a local variable, so
///   nothing but the framework's good manners kept it alive across the sheet.
/// - **A request resolves exactly once.** The continuation was overwritten by a second request
///   and never cleared after resuming, so a late or repeated callback could resume it twice, which
///   traps, or resolve a later request with an earlier one's answer.
/// - **A request has a presentation anchor.** The sheet is anchored to the foreground scene's key
///   window rather than to whatever the system guesses.
@MainActor
final class AppleAuthorizationPerformer: NSObject,
    AppleAuthorizationPerforming,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    typealias ControllerFactory = @MainActor (ASAuthorizationAppleIDRequest) -> ASAuthorizationController

    private let makeController: ControllerFactory
    private let now: @MainActor () -> Date
    private let notificationCenter: NotificationCenter
    private let anchorWindow: @MainActor () -> ASPresentationAnchor
    private let sceneState: @MainActor () -> String
    private let applicationState: @MainActor () -> String

    /// Strong, on purpose: see the type's comment.
    private var controller: ASAuthorizationController?
    private var pending: CheckedContinuation<AppleAuthorizationOutcome, Never>?
    private var startedAt: Date?
    private var sheetPresented = false
    private var resignObserver: (any NSObjectProtocol)?
    private var attemptNumber = 0

    init(
        makeController: @escaping ControllerFactory = { ASAuthorizationController(authorizationRequests: [$0]) },
        now: @escaping @MainActor () -> Date = { Date() },
        notificationCenter: NotificationCenter = .default,
        anchorWindow: @escaping @MainActor () -> ASPresentationAnchor = AppleAuthorizationPerformer.liveAnchor,
        sceneState: @escaping @MainActor () -> String = AppleAuthorizationPerformer.liveSceneState,
        applicationState: @escaping @MainActor () -> String = AppleAuthorizationPerformer.liveApplicationState
    ) {
        self.makeController = makeController
        self.now = now
        self.notificationCenter = notificationCenter
        self.anchorWindow = anchorWindow
        self.sceneState = sceneState
        self.applicationState = applicationState
        super.init()
    }

    var isInProgress: Bool { pending != nil }

    func perform(_ request: ASAuthorizationAppleIDRequest) async -> AppleAuthorizationOutcome {
        guard pending == nil else {
            return AppleAuthorizationOutcome(
                result: .failure(AppleAuthorizationError.alreadyInProgress),
                trace: trace(sheetPresented: false, millisecondsToResult: 0, attemptNumber: attemptNumber)
            )
        }

        attemptNumber += 1
        return await withCheckedContinuation { continuation in
            pending = continuation
            startedAt = now()
            sheetPresented = false
            resignObserver = notificationCenter.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.sheetPresented = true }
            }

            let controller = makeController(request)
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchorWindow()
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard isCurrent(controller) else { return }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            deliver(.failure(AuthenticationError.invalidAppleCredential))
            return
        }
        deliver(.success(AppleAuthorizationCredential(credential)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard isCurrent(controller) else { return }
        deliver(.failure(error))
    }

    // MARK: - Resolution

    /// A callback from a controller that is not the one this request started is a late answer to an
    /// earlier request, and must not resolve the current one.
    private func isCurrent(_ candidate: ASAuthorizationController) -> Bool {
        controller === candidate
    }

    /// Resolves the request once. A second call, or a call with nothing pending, does nothing.
    func deliver(_ result: Result<AppleAuthorizationCredential, Error>) {
        guard let continuation = pending else { return }
        pending = nil

        if let resignObserver { notificationCenter.removeObserver(resignObserver) }
        resignObserver = nil

        let elapsed = startedAt.map { max(0, Int((now().timeIntervalSince($0) * 1000).rounded())) } ?? 0
        startedAt = nil
        let outcome = AppleAuthorizationOutcome(
            result: result,
            trace: trace(sheetPresented: sheetPresented, millisecondsToResult: elapsed, attemptNumber: attemptNumber)
        )

        // This runs inside the controller's own callback, so its last reference is let go on the
        // next turn rather than while it is still on the stack.
        let finished = controller
        controller = nil
        Task { @MainActor in withExtendedLifetime(finished) {} }

        continuation.resume(returning: outcome)
    }

    private func trace(sheetPresented: Bool, millisecondsToResult: Int, attemptNumber: Int) -> AppleAuthorizationTrace {
        AppleAuthorizationTrace(
            sheetPresented: sheetPresented,
            millisecondsToResult: millisecondsToResult,
            sceneState: sceneState(),
            applicationState: applicationState(),
            attemptNumber: attemptNumber
        )
    }

    // MARK: - Live state

    /// The foreground scene's key window. A scene with no window yet gets one made for it, and only a
    /// process with no scene at all - nothing on screen to present over - falls back to a bare window.
    static func liveAnchor() -> ASPresentationAnchor {
        if let window = SignInPresentationWindow.connectedCandidates().first { return window }
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            return UIWindow(windowScene: scene)
        }
        return UIWindow(frame: .zero)
    }

    static func liveSceneState() -> String {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
        switch scene?.activationState {
        case .foregroundActive: return "foreground_active"
        case .foregroundInactive: return "foreground_inactive"
        case .background: return "background"
        case .unattached: return "unattached"
        case nil: return "none"
        @unknown default: return "unknown"
        }
    }

    static func liveApplicationState() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
}
