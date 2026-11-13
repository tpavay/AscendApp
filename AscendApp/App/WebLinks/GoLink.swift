import Foundation

/// A `https://ascendstepper.com/go` link, the one URL every lifecycle email and social bio points
/// at (`docs/universal-links.md`).
///
/// iOS hands these to Ascend, instead of Safari, only because the app claims the domain
/// (`applinks:ascendstepper.com` in `AscendApp.entitlements`) and the site vouches for the app
/// (`web/public/.well-known/apple-app-site-association`). Matching here is deliberately as narrow
/// as that file's paths - `/go` and anything under `/go/` - so a link the site never promised the
/// app cannot be reported as one it did.
struct GoLink: Equatable, Sendable {
    static let host = "ascendstepper.com"
    static let path = "/go"

    let source: Source

    init(source: Source) {
        self.source = source
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == Self.host,
              components.path == Self.path || components.path.hasPrefix(Self.path + "/") else {
            return nil
        }

        let rawSource = components.queryItems?.first { $0.name == "src" }?.value
        self.init(source: Source(rawQueryValue: rawSource))
    }
}

extension GoLink {
    /// The bounded set of `src` tags a link reports. An analytics parameter stays low-cardinality
    /// (`ascend-analytics`), so a tag nobody registered is `other` rather than whatever a stranger
    /// typed into a URL. Adding a tag means a case here beside its row in `docs/universal-links.md`.
    enum Source: String, CaseIterable, Sendable {
        case emailPaywallAbandoned = "email-paywall-abandoned"
        case emailFreeWeekUnused = "email-free-week-unused"
        case emailTrialReminder = "email-trial-reminder"
        case instagram
        case tiktok
        case youtube
        case facebook
        /// A link with no `src` at all.
        case missing = "none"
        /// A `src` that is not one of the tags above.
        case unrecognized = "other"

        init(rawQueryValue: String?) {
            let normalized = rawQueryValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""

            if normalized.isEmpty {
                self = .missing
            } else if let known = Self(rawValue: normalized), known != .missing, known != .unrecognized {
                self = known
            } else {
                self = .unrecognized
            }
        }
    }
}
