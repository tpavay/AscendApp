import SwiftUI

/// Emits a payload the first time a view instance appears, and never again for
/// that instance, so re-renders and state changes behind it cost nothing.
///
/// The guard is `@State`, which means it belongs to the view instance rather than
/// to the payload: a route rebuilt for a later visit gets a fresh guard and reports
/// that visit. Events and screen views share the one guard so view-level tracking
/// has a single mechanism.
struct TrackOnceModifier: ViewModifier {
    enum Payload {
        case event(any TelemetryEvent)
        case screen(TelemetryScreen)
    }

    let payload: Payload
    let telemetry: TelemetryManager

    @State private var hasTracked = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard hasTracked == false else { return }
            hasTracked = true

            switch payload {
            case .event(let event):
                telemetry.track(event)
            case .screen(let screen):
                telemetry.track(screen: screen)
            }
        }
    }
}
