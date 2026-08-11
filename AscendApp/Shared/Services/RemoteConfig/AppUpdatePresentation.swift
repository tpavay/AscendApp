import Foundation

/// The verdict ``AppVersionPolicy`` reaches about the installed build, and how it is shown.
///
/// The two cases are shown by different mechanisms on purpose. ``required`` is a route
/// (``AppRootRoute/updateRequired``) so nothing can cover it; ``recommended`` is a dismissible
/// sheet over whatever the climber is already doing.
enum AppUpdatePresentation: String, Equatable, Identifiable, Sendable {
    case required
    case recommended

    var id: Self { self }

    var title: String {
        switch self {
        case .required:
            "Update Required"
        case .recommended:
            "Update Ascend"
        }
    }

    var message: String {
        switch self {
        case .required:
            "Update Ascend to keep climbing. This version is no longer supported."
        case .recommended:
            "A newer version is ready. Update now, or keep climbing and do it later."
        }
    }

    /// Whether this verdict takes the whole app rather than prompting over it.
    ///
    /// The lockout is a route, never a sheet. Superwall presents outside `RootView`'s hierarchy and
    /// a second sheet at the same modifier level defers it, so a sheet was occludable by exactly the
    /// screens a stale build is most likely to be sitting on (#429).
    var locksOutApp: Bool { self == .required }

    var allowsInteractiveDismissal: Bool { self == .recommended }

    var showsLaterAction: Bool { self == .recommended }
}
