#if DEBUG
import CoreLocation
import MapboxMaps
import SwiftUI

/// Debug-only Mapbox renderer for validating Ascend's climb-board direction
/// without replacing the production MapKit globe.
struct ClimbMapboxPrototypeRenderer: View {
    let scene: AscendMapScene
    let selectedClimbId: String?
    let onSelect: (Climb) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var viewport: Viewport = .camera(
        center: CLLocationCoordinate2D(latitude: 18.0, longitude: 8.0),
        zoom: 1.35,
        bearing: 0,
        pitch: 0
    )

    var body: some View {
        MapboxMaps.Map(viewport: $viewport) {
            ForEvery(scene.landmarks) { landmark in
                MapViewAnnotation(coordinate: landmark.climb.coordinate) {
                    Button {
                        select(landmark.climb)
                    } label: {
                        ClimbPinView(
                            climb: landmark.climb,
                            isCompleted: landmark.state == .completed,
                            isHighlighted: isHighlighted(landmark)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: landmark))
                    .accessibilityHint(landmark.climb.isAvailable ? "Preview climb details" : "Preview coming soon climb")
                }
                .allowOverlap(true)
                .variableAnchors([
                    ViewAnnotationAnchorConfig(anchor: .bottom)
                ])
            }
        }
        .mapStyle(.standard(lightPreset: colorScheme == .dark ? .night : .dusk))
    }

    private func select(_ climb: Climb) {
        onSelect(climb)
        withViewportAnimation {
            viewport = focusedViewport(for: climb)
        }
    }

    private func focusedViewport(for climb: Climb) -> Viewport {
        .camera(
            center: climb.coordinate,
            zoom: focusedZoom(for: climb),
            bearing: 0,
            pitch: Double(ClimbCameraFraming.pitch(for: climb))
        )
    }

    private func focusedZoom(for climb: Climb) -> CGFloat {
        if ClimbCameraFraming.isNatural(climb) {
            return 11.5
        }

        let height = max(climb.referenceHeightMeters, 60)
        let t = min(max((height - 80) / (600 - 80), 0), 1)
        return 16.2 - CGFloat(t) * 1.8
    }

    private func isHighlighted(_ landmark: AscendMapLandmark) -> Bool {
        landmark.isHighlighted || selectedClimbId == landmark.climb.id
    }

    private func accessibilityLabel(for landmark: AscendMapLandmark) -> String {
        if landmark.climb.isComingSoon {
            return "Coming soon climb, \(landmark.climb.displayLocation)"
        }
        return "\(landmark.climb.name), \(landmark.climb.displayLocation)"
    }
}
#endif
