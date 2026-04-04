import MapKit
import SwiftUI

struct GlobeView: View {
    @Bindable var viewModel: GlobeViewModel
    let onSelectClimb: (Climb) -> Void

    var body: some View {
        mapView
            .contentShape(Rectangle())
    }

    private var mapView: some View {
        Map(position: cameraPositionBinding, interactionModes: [.pan, .zoom]) {
            climbAnnotations
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControls {}
        .onMapCameraChange(frequency: .continuous) { _ in
            viewModel.mapCameraDidChange()
        }
    }

    private var cameraPositionBinding: Binding<MapCameraPosition> {
        Binding(
            get: { viewModel.cameraPosition },
            set: { viewModel.cameraPosition = $0 }
        )
    }

    @MapContentBuilder
    private var climbAnnotations: some MapContent {
        ForEach(viewModel.visibleClimbs) { climb in
            Annotation("", coordinate: climb.coordinate, anchor: .bottom) {
                pinButton(for: climb)
            }
        }
    }

    private func pinButton(for climb: Climb) -> some View {
        Button {
            onSelectClimb(climb)
        } label: {
            ClimbPinView(
                climb: climb,
                isCompleted: viewModel.isCompleted(climb),
                isActive: viewModel.isActive(climb),
                isHighlighted: viewModel.previewSummary?.climb.id == climb.id
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(climb.name), \(climb.displayLocation)")
        .accessibilityHint("Preview climb details")
    }
}

#Preview("Default") {
    GlobeView(
        viewModel: {
            let vm = GlobeViewModel()
            vm.visibleClimbs = [.preview]
            return vm
        }(),
        onSelectClimb: { _ in }
    )
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}

#Preview("No Climbs") {
    GlobeView(
        viewModel: GlobeViewModel(),
        onSelectClimb: { _ in }
    )
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}
