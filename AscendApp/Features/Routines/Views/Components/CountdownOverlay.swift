import SwiftUI

struct CountdownOverlay: View {
    let value: Int

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            // Countdown number
            Text("\(value)")
                .font(.system(size: 180, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onChange(of: value) { _, newValue in
            // Animate on value change
            withAnimation(.easeOut(duration: 0.15)) {
                scale = 1.3
                opacity = 0.5
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeIn(duration: 0.25)) {
                    scale = 1.0
                    opacity = 1.0
                }
            }
        }
    }
}

#Preview {
    CountdownOverlay(value: 3)
}
