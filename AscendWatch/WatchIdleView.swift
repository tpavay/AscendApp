import SwiftUI

/// The whole watch face for now. The wrist has nothing to show until the phone
/// starts a session and mirrors it here, so the only honest state is the one
/// that says what is missing and what to do about it.
struct WatchIdleView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.stair.stepper")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            Text("No climb running")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Start one on your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    WatchIdleView()
}
