import SwiftUI

struct ImportBellFramePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let nextFrame = nextValue()
        guard nextFrame != .zero else { return }
        value = nextFrame
    }
}
