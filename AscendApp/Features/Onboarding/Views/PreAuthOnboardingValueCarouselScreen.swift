import SwiftUI

struct PreAuthOnboardingValueCarouselScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0
    @State private var isShowingSignUp = false

    var body: some View {
        OnboardingScaffold(
            backAction: { dismiss() },
            background: {
                Color.black
            },
            content: { _ in
                OnboardingValueCarouselView(
                    selectedIndex: $selectedIndex,
                    pages: OnboardingValuePages.all,
                    onFinish: { isShowingSignUp = true }
                )
                .ignoresSafeArea()
            }
        )
        .navigationDestination(isPresented: $isShowingSignUp) {
            SignUpView()
        }
    }
}

#Preview {
    NavigationStack {
        PreAuthOnboardingValueCarouselScreen()
    }
}
