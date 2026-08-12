import SwiftUI

extension View {
    func trackOnce(
        _ event: any TelemetryEvent,
        telemetry: TelemetryManager = .shared
    ) -> some View {
        modifier(TrackOnceModifier(event: event, telemetry: telemetry))
    }
}
