import SwiftUI

extension View {
    func trackOnce(
        _ event: any TelemetryEvent,
        telemetry: TelemetryManager = .shared
    ) -> some View {
        modifier(TrackOnceModifier(payload: .event(event), telemetry: telemetry))
    }

    func trackOnce(
        screen: TelemetryScreen,
        telemetry: TelemetryManager = .shared
    ) -> some View {
        modifier(TrackOnceModifier(payload: .screen(screen), telemetry: telemetry))
    }
}
