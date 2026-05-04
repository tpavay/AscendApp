import SwiftUI

struct LiveSessionCountdownOverlay: View {
    let value: Int

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Text("\(value)")
                .font(.montserratBold(size: 180))
                .foregroundStyle(.white)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onChange(of: value) { _, _ in
            withAnimation(.easeOut(duration: 0.15)) {
                scale = 1.3
                opacity = 0.5
            }

            Task {
                try await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeIn(duration: 0.25)) {
                    scale = 1.0
                    opacity = 1.0
                }
            }
        }
    }
}

#Preview {
    LiveSessionCountdownOverlay(value: 3)
}
