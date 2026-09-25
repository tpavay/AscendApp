import SwiftUI

/// How much of the screen's bottom the custom tab bar covers, beyond the window's
/// own safe area.
///
/// `MainTabView` draws the tab bar with `safeAreaInset`, but the tab content is hosted
/// by a UIKit container that reports only the window's insets, so a screen inside a
/// tab sees the home indicator and not the bar. Every scrolling tab root pads for
/// that by hand; the globe's sheet cannot, because its resting heights are measured
/// from the bottom of the covered area. `MainTabView` measures the bar and publishes
/// its height here; the globe screens add it to the safe-area bottom.
private struct TabBarOverlayHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var tabBarOverlayHeight: CGFloat {
        get { self[TabBarOverlayHeightKey.self] }
        set { self[TabBarOverlayHeightKey.self] = newValue }
    }
}
