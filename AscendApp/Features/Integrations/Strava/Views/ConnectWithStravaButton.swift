import SwiftUI

/// Strava's official "Connect with Strava" button, drawn from the artwork in
/// its brand guidelines at the specified 48pt height and never altered. While
/// a connection is in flight the button is disabled and a spinner sits beside
/// it rather than on top of it.
struct ConnectWithStravaButton: View {
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                Image("connect-with-strava")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityLabel("Connect with Strava")

            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
