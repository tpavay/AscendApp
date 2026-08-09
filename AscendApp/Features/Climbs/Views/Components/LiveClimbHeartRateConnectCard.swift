import SwiftUI

/// The post-climb offer to put heart rate on the climb the climber just finished.
///
/// Enrichment used to be reachable only by climbers who had already connected Apple Health,
/// which meant everyone else got nothing and was never told why (#438). This is the moment
/// that earns the ask: the work is done, the numbers are on screen, and the one number
/// missing is the one connecting Health would supply.
///
/// It never blocks the summary. Done stays where it was, this card sits with the other
/// cards, and dismissing it costs one tap.
struct LiveClimbHeartRateConnectCard: View {
    let isConnecting: Bool
    let onConnect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.red.opacity(0.16)))

                VStack(alignment: .leading, spacing: 5) {
                    Text("NO HEART RATE ON THIS CLIMB")
                        .font(.montserratBold(size: 12))
                        .foregroundStyle(.accent)

                    Text("Connect Apple Health and Ascend pulls it from whatever you wore.")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: onConnect) {
                    HStack(spacing: 8) {
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.black)
                        }

                        Text(isConnecting ? "Connecting" : "Connect Apple Health")
                            .font(.montserratBold(size: 12))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule(style: .continuous).fill(Color.accent))
                }
                .buttonStyle(.plain)
                .disabled(isConnecting)
                .opacity(isConnecting ? 0.62 : 1)

                Button("Not now", action: onDismiss)
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .buttonStyle(.plain)
                    .disabled(isConnecting)

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack {
        LiveClimbHeartRateConnectCard(isConnecting: false, onConnect: {}, onDismiss: {})
        LiveClimbHeartRateConnectCard(isConnecting: true, onConnect: {}, onDismiss: {})
    }
    .padding(20)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
