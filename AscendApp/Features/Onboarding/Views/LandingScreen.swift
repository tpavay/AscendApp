import SwiftUI

struct LandingScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 18) {
                Image("AppIconInternal")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.accent)
                    .frame(width: 120, height: 120)
                    .shadow(color: .accent.opacity(0.35), radius: 16, y: 6)

                Text("Ascend")
                    .font(.montserratBold)
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .kerning(0.5)
                    .shadow(color: colorScheme == .dark ? .black.opacity(0.6) : .clear, radius: 10, y: 4)

                Text("Elevate Your Stair Climbing Game")
                    .font(.montserratMedium)
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.72) : .gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, -4)

                VStack(spacing: -12) {
                    NavigationLink(destination: SignUpView()) {
                        Text("Continue")
                            .font(.montserratSemiBold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 55)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.accent)
                            )
                            .padding()
                    }
                }

                Spacer(minLength: 24)
        }
        .padding(.top, 180)
        .themedBackground()
    }
}

#Preview {
    NavigationStack {
        LandingScreen()
    }
}
