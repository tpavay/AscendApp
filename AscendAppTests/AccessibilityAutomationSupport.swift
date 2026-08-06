import Foundation
import Testing
import UIKit

/// Runs `body` with the in-process accessibility runtime on, the way UI automation does.
///
/// SwiftUI builds its accessibility tree only while an assistive technology is listening; with
/// nothing listening a hosted screen publishes no elements at all and there is no control to press
/// and nothing to count. There is no public switch for it, and the switch is process-wide - a suite
/// that leaves it on changes how every later test in the host builds its tree - so every hosting
/// suite goes through here rather than flipping it itself.
@MainActor
func withAccessibilityAutomation<Result>(
    _ body: () async throws -> Result
) async rethrows -> Result {
    setAccessibilityAutomationEnabled(true)
    defer { setAccessibilityAutomationEnabled(false) }

    return try await body()
}

/// Every accessibility element the hosted view publishes, in tree order. SwiftUI draws its controls
/// rather than backing them with `UIView`s, so this tree is the only in-process handle on them.
@MainActor
func accessibilityElements(under root: UIView) -> [NSObject] {
    var found: [NSObject] = []

    func visit(_ node: NSObject) {
        let count = node.accessibilityElementCount()
        if count != NSNotFound {
            for index in 0..<count {
                guard let child = node.accessibilityElement(at: index) as? NSObject else {
                    continue
                }

                found.append(child)
                visit(child)
            }
        }

        if let view = node as? UIView {
            for subview in view.subviews {
                visit(subview)
            }
        }
    }

    visit(root)
    return found
}

@MainActor
private func setAccessibilityAutomationEnabled(_ isEnabled: Bool) {
    typealias SetAutomationEnabled = @convention(c) (Bool) -> Void

    guard
        let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
        let symbol = dlsym(library, "_AXSSetAutomationEnabled")
    else {
        Issue.record("The accessibility runtime could not be started")
        return
    }

    unsafeBitCast(symbol, to: SetAutomationEnabled.self)(isEnabled)
}
