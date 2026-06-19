import SwiftUI

struct OnboardingValueShowcaseUpperBackground: View {
    let imageName: String
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: height)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.18),
                                Color.black.opacity(0.02),
                                Color.black.opacity(0.28)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea()
    }
}
