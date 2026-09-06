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
    // A hosted node is reachable both as its container's accessibility element and through that
    // container's subviews, so an undeduped walk returns the very same objects twice and every
    // count a caller takes is double what the screen actually publishes.
    var visited: Set<ObjectIdentifier> = []

    func visit(_ node: NSObject) {
        let count = node.accessibilityElementCount()
        if count != NSNotFound {
            for index in 0..<count {
                guard let child = node.accessibilityElement(at: index) as? NSObject,
                      visited.insert(ObjectIdentifier(child)).inserted else {
                    continue
                }

                found.append(child)
                visit(child)
            }
        }

        // A wheel picker is one element whose value is the selection; its drums are hundreds of
        // rows each, and with the automation runtime listening a walk that descends into them
        // materialises every row's accessibility node. Hosting the onboarding birthday wheel
        // measured 634 -> 2,560 MB of resident memory on that one descent.
        if let view = node as? UIView, !(view is UIPickerView), !(view is UIDatePicker) {
            for subview in view.subviews {
                visit(subview)
            }
        }
    }

    visit(root)
    return found
}

/// The same tree, read once it is actually there.
///
/// SwiftUI publishes its accessibility tree on its own schedule after automation starts listening,
/// so a single read straight after `layoutIfNeeded()` can land on an empty tree whenever another
/// suite is competing for the main actor. The hosted screen then reads as having no controls and no
/// modal at all, which fails as though the view were wrong. Polls until `isReady` holds, and returns
/// whatever the tree holds once the budget is spent so the caller's own assertion reports the real
/// shortfall.
///
/// The budget is counted in reads that actually happened rather than in wall-clock time, because the
/// competition this poll exists to survive is exactly what stops the clock from buying any. A hosting
/// test shares the main actor with the rest of the run, and one `@MainActor` test that never suspends
/// holds it for as long as it takes - so a five-second deadline can expire having granted this loop
/// two turns, and the empty tree it then reports is the starvation rather than the view. Measured on
/// a quiet host, the tree fills in roughly fifteen reads; the budget below is an order of magnitude
/// more, and under contention it waits for those reads however long the main actor makes it wait.
@MainActor
func settledAccessibilityElements(
    under root: UIView,
    reading budget: Int = 250,
    until isReady: ([NSObject]) -> Bool = { $0.isEmpty == false }
) async throws -> [NSObject] {
    var remainingReads = max(1, budget)

    while true {
        let elements = accessibilityElements(under: root)
        remainingReads -= 1
        if isReady(elements) || remainingReads == 0 {
            return elements
        }

        root.setNeedsLayout()
        root.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// Activates the control a climber would tap, through the same accessibility action VoiceOver uses.
@MainActor
func activateAccessibilityElement(
    in root: UIView,
    matching isMatch: (NSObject) -> Bool
) throws {
    let elements = accessibilityElements(under: root)
    let match = elements.first(where: isMatch)
    let element = try #require(
        match,
        """
        No matching accessibility element on the hosted screen. \
        Found: \(elements.map { "\(type(of: $0)): \($0.accessibilityLabel ?? "nil")" })
        """
    )

    #expect(element.accessibilityActivate())
}

@MainActor
func activateAccessibilityElement(labelled label: String, in root: UIView) throws {
    try activateAccessibilityElement(in: root) { $0.accessibilityLabel == label }
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
