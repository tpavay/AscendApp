import SwiftUI

struct LandingScreen: View {

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(colors: [.night, .jetLighter],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("AppIconInternal")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.accent)
                    .frame(width: 120, height: 120)
                    .shadow(color: .accent.opacity(0.35), radius: 16, y: 6)

                Text("Ascend")
                    .font(.montserratBold)
                    .foregroundStyle(.white)
                    .kerning(0.5)
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 4)

                Text("Elevate Your Stairmaster Game")
                    .font(.montserratMedium)
                    .foregroundStyle(.white.opacity(0.72))
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
        }
    }
}

#Preview {
    NavigationStack {
        LandingScreen()
    }
}
