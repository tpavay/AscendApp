import MapKit
import SwiftUI

/// MapKit implementation of the climb map. This is the ONLY file that knows how
/// to draw the browse globe with MapKit — it consumes an engine-agnostic
/// `AscendMapScene` and reports user interactions back out.
///
/// **Migration path:** to move the globe to another engine (Mapbox / MapLibre /
/// a custom globe), add a sibling renderer (e.g. `ClimbMapboxRenderer`) that
/// draws the same `AscendMapScene`, then swap which renderer `GlobeView`
/// instantiates. Keep ALL map-engine code inside renderers like this so the
/// view model and scene stay engine-free.
///
/// Camera handling is intentionally still MapKit-typed here (a
/// `Binding<MapCameraPosition>`): the camera-control contract is best abstracted
/// when a second engine actually exists, rather than guessed from one. The
/// scene already abstracts the bulk of the work (the landmark layer).
struct ClimbMapKitRenderer: View {
    let scene: AscendMapScene
    @Binding var cameraPosition: MapCameraPosition
    let onSelect: (Climb) -> Void
    let onCameraChange: (MapCameraUpdateContext) -> Void

    var body: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            landmarkAnnotations
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControls {}
        .onMapCameraChange(frequency: .continuous) { context in
            onCameraChange(context)
        }
    }

    @MapContentBuilder
    private var landmarkAnnotations: some MapContent {
        ForEach(scene.landmarks) { landmark in
            Annotation("", coordinate: landmark.climb.coordinate, anchor: .bottom) {
                pin(for: landmark)
            }
        }
    }

    private func pin(for landmark: AscendMapLandmark) -> some View {
        Button {
            onSelect(landmark.climb)
        } label: {
            ClimbPinView(
                climb: landmark.climb,
                isCompleted: landmark.state == .completed,
                isHighlighted: landmark.isHighlighted
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: landmark.climb))
        .accessibilityHint(landmark.climb.isAvailable ? "Preview climb details" : "Preview coming soon climb")
    }

    private func accessibilityLabel(for climb: Climb) -> String {
        if climb.isComingSoon {
            return "Coming soon climb, \(climb.displayLocation)"
        }
        return "\(climb.name), \(climb.displayLocation)"
    }
}
