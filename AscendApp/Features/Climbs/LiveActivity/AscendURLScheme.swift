import Foundation

/// The URL scheme this build answers to: `ascendapp` for the App Store build, `ascendapp-stg`
/// and `ascendapp-dev` for the others (`ASCEND_URL_SCHEME`).
///
/// Every build used to register `ascendapp`, so with more than one installed iOS handed a link
/// to whichever it chose - a production climber connecting Strava was sent back into the staging
/// build. Each build now claims only its own scheme, and every link Ascend makes for itself
/// uses it.
///
/// Lives beside the Live Activity because this folder is compiled into the widget extension
/// too, whose links must open the build that started the climb.
enum AscendURLScheme {
    static let infoKey = "AscendURLScheme"
    static let production = "ascendapp"

    static var current: String {
        resolved(from: Bundle.main.object(forInfoDictionaryKey: infoKey))
    }

    static func resolved(from infoValue: Any?) -> String {
        guard let scheme = (infoValue as? String)?.trimmingCharacters(in: .whitespaces),
              !scheme.isEmpty,
              !scheme.hasPrefix("$(") else {
            return production
        }
        return scheme.lowercased()
    }
}
