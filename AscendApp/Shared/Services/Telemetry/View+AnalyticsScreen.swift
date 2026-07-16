import SwiftUI

extension View {
    func analyticsScreen(_ screen: TelemetryScreen) -> some View {
        modifier(AnalyticsScreenModifier(screen: screen))
    }
}
