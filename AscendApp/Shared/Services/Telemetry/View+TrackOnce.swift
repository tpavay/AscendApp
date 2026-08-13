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

    /// Reports a route boundary from the reviewed catalog. This is the overload product
    /// surfaces use; the one above exists for the telemetry layer and its tests.
    func trackOnce(
        screen: TelemetryScreenName,
        telemetry: TelemetryManager = .shared
    ) -> some View {
        trackOnce(screen: TelemetryScreen(screen), telemetry: telemetry)
    }
}
