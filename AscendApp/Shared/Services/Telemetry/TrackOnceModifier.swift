import SwiftUI

/// Emits an event the first time a view instance appears, and never again for
/// that instance, so re-renders and state changes behind it cost nothing.
///
/// The guard is `@State`, which means it belongs to the view instance rather than
/// to the event: a route rebuilt for a later visit gets a fresh guard and reports
/// that visit.
struct TrackOnceModifier: ViewModifier {
    let event: any TelemetryEvent
    let telemetry: TelemetryManager

    @State private var hasTracked = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard hasTracked == false else { return }
            hasTracked = true
            telemetry.track(event)
        }
    }
}
