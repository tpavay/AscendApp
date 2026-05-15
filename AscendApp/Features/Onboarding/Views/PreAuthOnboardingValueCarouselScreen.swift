import SwiftUI

struct PreAuthOnboardingValueCarouselScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0
    @State private var isShowingSignUp = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                OnboardingValueCarouselView(
                    selectedIndex: $selectedIndex,
                    pages: OnboardingValuePages.all,
                    onFinish: { isShowingSignUp = true }
                )

                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .padding(.leading, 18)
                .padding(.top, 8)
            }
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
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
