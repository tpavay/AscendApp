import Foundation

/// A strict numeric app version with one to three dot-separated components.
///
/// Ascend's `CFBundleShortVersionString` is currently `1.0`, while operators may use the explicit
/// three-component form `1.0.0`. Missing trailing components therefore compare as zero. All other
/// syntax fails parsing so an uncertain version can never block the app.
struct SemanticAppVersion: Comparable, Sendable {
    private let components: [UInt]

    init?(_ rawValue: String?) {
        guard let rawValue,
              rawValue.isEmpty == false,
              rawValue == rawValue.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let rawComponents = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(rawComponents.count) else { return nil }

        var parsedComponents: [UInt] = []
        parsedComponents.reserveCapacity(3)

        for rawComponent in rawComponents {
            guard rawComponent.isEmpty == false,
                  rawComponent.allSatisfy({ $0.isASCII && $0.isNumber }),
                  rawComponent.count == 1 || rawComponent.first != "0",
                  let component = UInt(rawComponent) else {
                return nil
            }
            parsedComponents.append(component)
        }

        parsedComponents.append(contentsOf: repeatElement(0, count: 3 - parsedComponents.count))
        components = parsedComponents
    }

    static func < (lhs: SemanticAppVersion, rhs: SemanticAppVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}
