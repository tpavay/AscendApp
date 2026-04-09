import SwiftUI

struct AnalyticsScreenModifier: ViewModifier {
    let screen: TelemetryScreen

    @State private var hasTracked = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !hasTracked else { return }
            hasTracked = true
            TelemetryManager.shared.track(screen: screen)
        }
    }
}
