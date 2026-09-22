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
/// when a second engine actually exists, rather than guessed from one.
///
/// Clustering is overlap-driven: on every camera change the renderer projects the
/// landmarks to screen points through `MapProxy` and asks `ClimbMapClustering`
/// which markers would sit on top of each other. Those draw as one "N climbs" pill
/// until they separate; everything else is its own marker at every zoom. The map
/// style never changes with zoom, so a camera move never rebuilds the tiles or
/// the annotations under the climber.
struct ClimbMapKitRenderer: View {
    let scene: AscendMapScene
    @Binding var cameraPosition: MapCameraPosition
    let onSelect: (Climb) -> Void
    let onSelectCluster: (AscendMapCluster) -> Void
    let onCameraChange: (MapCameraUpdateContext) -> Void

    @State private var layer: ClimbMapClustering.Layer = .empty

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: .all) {
                ForEach(layer.clusters) { cluster in
                    Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                        clusterPill(for: cluster)
                    }
                }

                ForEach(layer.pins) { landmark in
                    Annotation("", coordinate: landmark.climb.coordinate, anchor: .center) {
                        marker(for: landmark)
                    }
                }
            }
            // One style at every zoom: imagery, with streets and place labels arriving
            // as the camera descends. Points of interest stay off; the only markers on
            // this map are Ascend's climbs.
            .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls {}
            .onMapCameraChange(frequency: .continuous) { context in
                onCameraChange(context)
                regroup(with: proxy)
            }
            .onChange(of: sceneSignature) { _, _ in
                regroup(with: proxy)
            }
            .onAppear {
                regroup(with: proxy)
            }
        }
    }

    /// The facts a regroup must notice without a camera move: a landmark added or
    /// removed, its state or count changed, or the highlighted one changed.
    private var sceneSignature: [String] {
        scene.landmarks.map {
            "\($0.id)|\($0.state)|\($0.isHighlighted)|\($0.completedClimberCount.map(String.init) ?? "-")"
        }
    }

    private func regroup(with proxy: MapProxy) {
        var points: [String: CGPoint] = [:]
        for landmark in scene.landmarks {
            if let point = proxy.convert(landmark.climb.coordinate, to: .local) {
                points[landmark.id] = point
            }
        }
        let next = ClimbMapClustering.layer(for: scene.landmarks, points: points)
        if next != layer {
            layer = next
        }
    }

    private func clusterPill(for cluster: AscendMapCluster) -> some View {
        Button {
            onSelectCluster(cluster)
        } label: {
            ClimbClusterBubbleView(cluster: cluster)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cluster.count) climbs grouped here")
        .accessibilityHint("Zoom in to see each one")
    }

    private func marker(for landmark: AscendMapLandmark) -> some View {
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
                    .offset(y: 16)
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

/// A climb's name under its marker, shown from country zoom in.
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
