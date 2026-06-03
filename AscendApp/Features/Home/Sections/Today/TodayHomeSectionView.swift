import SwiftUI

struct TodayHomeSectionView: View {
    @Bindable var viewModel: GlobeViewModel
    let onOpenClimb: (Climb) -> Void

    var body: some View {
        ClimbCardView(
            viewModel: viewModel,
            onOpenClimb: onOpenClimb
        )
    }
}
