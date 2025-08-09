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

            // Soft accent glow
            RadialGradient(colors: [.accent.opacity(0.25), .clear],
                           center: .center,
                           startRadius: 0,
                           endRadius: 340)
                .blur(radius: 8)

            VStack(spacing: 18) {
                Image("AppIconInternal")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.accent)
                    .frame(width: 96, height: 96)
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

                Button(action: {}) {
                    Text("Continue")
                        .font(.montserratSemiBold)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.accent)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(.accent.darker(by: 0.18), lineWidth: 1)
                                )
                        )
                }
                .shadow(color: .accent.opacity(0.35), radius: 14, y: 8)
                .padding(.top, 8)
                .padding(.horizontal, 24)

                Spacer(minLength: 24)
            }
            .padding(.top, 180)
        }
    }
}

#Preview { LandingScreen() }
