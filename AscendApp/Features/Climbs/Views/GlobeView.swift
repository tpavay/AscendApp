import MapKit
import SwiftUI

/// The browse globe. A thin host that builds an engine-agnostic
/// `AscendMapScene` from the view model and hands it to a map renderer. The
/// renderer (`ClimbMapKitRenderer` today) owns all map-engine specifics, so
/// switching engines later is a renderer swap — not a globe rewrite.
struct GlobeView: View {
    @Bindable var viewModel: GlobeViewModel
    let onSelectClimb: (Climb) -> Void

    var body: some View {
        ClimbMapKitRenderer(
            scene: viewModel.mapScene,
            cameraPosition: $viewModel.cameraPosition,
            onSelect: onSelectClimb,
            onCameraChange: { context in viewModel.mapCameraDidChange(context) }
        )
        .contentShape(Rectangle())
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
