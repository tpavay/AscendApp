import SwiftUI

struct LandingScreen: View {
    private let bgTop   = Color(hex: "0B0B0B")
    private let bgBottom = Color(hex: "141414")

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(colors: [bgTop, bgBottom],
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
                        Text("Create New Account")
                            .font(.montserratSemiBold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 55)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.accent.darker(by: 0.2))
                            )
                            .padding()
                    }
                    NavigationLink(destination: SignInView()) {
                        Text("Login to existing account")
                            .font(.montserratSemiBold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 55)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.accent.darker(by: 0.2))
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
