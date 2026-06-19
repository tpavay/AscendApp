import SwiftUI

struct WorkoutHeartRateRecoveryCard: View {
    let connectionState: AppleHealthConnectionState
    let isFetching: Bool
    let message: String?
    let effectiveColorScheme: ColorScheme
    let onFetch: () -> Void

    private var primaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.58)
    }

    private var cardFill: Color {
        effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06)
    }

    private var borderColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15)
    }

    private var title: String {
        switch connectionState {
        case .connected:
            return "Waiting for heart-rate data"
        case .neverConnected:
            return "Connect Apple Health"
        case .revoked:
            return "Apple Health access is off"
        case .unavailable:
            return "Apple Health unavailable"
        }
    }

    private var detail: String {
        if let message, !message.isEmpty {
            return message
        }

        switch connectionState {
        case .connected:
            return "Apple Watch workouts can take a few minutes to sync. Fetch again after Health finishes writing the workout."
        case .neverConnected:
            return "Connect Apple Health to pull heart-rate data from your Watch workout."
        case .revoked:
            return "Re-enable Ascend in Health permissions, then return here to fetch heart-rate data."
        case .unavailable:
            return "This device cannot read Apple Health data."
        }
    }

    private var actionTitle: String? {
        switch connectionState {
        case .connected:
            return "Fetch"
        case .neverConnected:
            return "Connect"
        case .revoked, .unavailable:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Heart Rate")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(primaryTextColor)

                Spacer()

                if isFetching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.red)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "heart")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(.red.opacity(effectiveColorScheme == .dark ? 0.16 : 0.1))
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(primaryTextColor)

                    Text(detail)
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)

                    if let actionTitle {
                        Button(action: onFetch) {
                            Label(actionTitle, systemImage: "arrow.clockwise")
                                .font(.montserratBold(size: 12))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accent)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isFetching)
                        .opacity(isFetching ? 0.62 : 1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        WorkoutHeartRateRecoveryCard(
            connectionState: .connected,
            isFetching: false,
            message: nil,
            effectiveColorScheme: .dark,
            onFetch: {}
        )

        WorkoutHeartRateRecoveryCard(
            connectionState: .neverConnected,
            isFetching: true,
            message: nil,
            effectiveColorScheme: .dark,
            onFetch: {}
        )
    }
    .padding(20)
    .background(Color.black)
}
