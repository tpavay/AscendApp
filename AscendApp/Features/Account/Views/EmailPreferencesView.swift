import SwiftUI

/// The Email preference screen. `EmailPreferencesContentView` is what it shows;
/// this owns the scroll, the navigation chrome, and when the server is re-read.
struct EmailPreferencesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: EmailPreferencesViewModel

    init(viewModel: EmailPreferencesViewModel = EmailPreferencesViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            EmailPreferencesContentView(viewModel: viewModel)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
        }
        .themedBackground()
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            Task {
                // The unsubscribe link changes this preference outside the app,
                // so the server value is re-read rather than trusted from launch.
                await viewModel.load()
            }
        }
    }
}

#Preview {
    NavigationStack {
        EmailPreferencesView()
    }
}
