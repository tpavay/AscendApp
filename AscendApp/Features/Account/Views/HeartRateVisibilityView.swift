import SwiftUI

/// Settings -> Privacy -> Heart rate. `HeartRateVisibilityContentView` is what it shows; this
/// owns the scroll, the navigation chrome, and building the service from the signed-in account.
struct HeartRateVisibilityView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: HeartRateVisibilityViewModel?

    var body: some View {
        ScrollView {
            if let viewModel {
                HeartRateVisibilityContentView(viewModel: viewModel)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
            }
        }
        .themedBackground()
        .navigationTitle("Heart Rate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .task {
            guard viewModel == nil, let user = authVM.user else { return }
            let model = HeartRateVisibilityViewModel(
                service: HeartRateVisibilityService(
                    userId: user.uid,
                    joinedAt: user.metadata.creationDate,
                    modelContext: modelContext
                )
            )
            viewModel = model
            await model.load()
        }
        .trackOnce(screen: .heartRateVisibility)
    }
}
