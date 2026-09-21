import MapKit
import SwiftUI

/// MapKit implementation of the climb map. This is the ONLY file that knows how
/// to draw the globe with MapKit: it consumes an engine-agnostic `AscendMapScene`
/// and reports user interactions back out.
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
///
/// What the scene's zoom band changes here: at world zoom the markers gather into
/// "N climbs" pills; from country zoom in every marker carries its name; at city
/// zoom the imagery gains streets and place labels. Each is a function of the band,
/// so the annotation set changes once per crossing and never mid-pinch. A marker
/// itself is `ClimbMarkerView`: the finisher count, the First Ascent mark, and the
/// viewer's own check.
struct ClimbMapKitRenderer: View {
    let scene: AscendMapScene
    @Binding var cameraPosition: MapCameraPosition
    let onSelect: (Climb) -> Void
    let onSelectCluster: (AscendMapCluster) -> Void
    let onCameraChange: (MapCameraUpdateContext) -> Void

    var body: some View {
        let layer = scene.layer

        Map(position: $cameraPosition, interactionModes: .all) {
            ForEach(layer.clusters) { cluster in
                Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                    clusterBubble(for: cluster)
                }
            }

            ForEach(layer.pins) { landmark in
                Annotation("", coordinate: landmark.climb.coordinate, anchor: .center) {
                    pin(for: landmark)
                }
            }
        }
        .mapStyle(mapStyle)
        .mapControls {}
        .onMapCameraChange(frequency: .continuous) { context in
            onCameraChange(context)
        }
    }

    /// Imagery is the globe; streets join it only at city zoom. Points of interest
    /// stay off at every zoom: the only markers on this map are Ascend's climbs.
    private var mapStyle: MapStyle {
        if scene.zoomBand.showsStreets {
            return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false)
        }
        return .imagery(elevation: .realistic)
    }

    private func clusterBubble(for cluster: AscendMapCluster) -> some View {
        Button {
            onSelectCluster(cluster)
        } label: {
            ClimbClusterBubbleView(cluster: cluster)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cluster.count) climbs grouped here")
        .accessibilityHint("Zoom in to see each one")
    }

    private func pin(for landmark: AscendMapLandmark) -> some View {
        Button {
            onSelect(landmark.climb)
        } label: {
            // The label is an overlay, not a sibling, so the annotation's anchor stays
            // the marker's centre and the name hangs below the landmark.
            ClimbMarkerView(
                climb: landmark.climb,
                completedClimberCount: landmark.completedClimberCount,
                isCompleted: landmark.state == .completed,
                isHighlighted: landmark.isHighlighted
            )
            .overlay(alignment: .bottom) {
                if scene.showsNames {
                    ClimbPinNameLabel(
                        climb: landmark.climb,
                        isHighlighted: landmark.isHighlighted
                    )
                    .offset(y: 18)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ClimbMarkerView.accessibilityDescription(
            climb: landmark.climb,
            completedClimberCount: landmark.completedClimberCount,
            isCompleted: landmark.state == .completed
        ))
        .accessibilityHint(landmark.climb.isAvailable ? "Preview climb details" : "Preview coming soon climb")
    }
}

/// A climb's name under its pin, shown from country zoom in. The label hangs below
/// the pin's anchor so the pin tip stays on the landmark.
private struct ClimbPinNameLabel: View {
    let climb: Climb
    let isHighlighted: Bool

    var body: some View {
        Text(climb.isComingSoon ? "Coming soon" : climb.name)
            .font(.montserratSemiBold(size: 10))
            .foregroundStyle(.white.opacity(isHighlighted ? 1 : 0.9))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.58))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(climb.tier.color.opacity(isHighlighted ? 0.9 : 0.4), lineWidth: 1)
            )
            .fixedSize()
            .accessibilityHidden(true)
    }
}
