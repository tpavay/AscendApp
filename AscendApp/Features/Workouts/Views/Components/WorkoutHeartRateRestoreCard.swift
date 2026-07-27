import SwiftUI

struct WorkoutHeartRateRestoreCard: View {
    let status: WorkoutHeartRateRestoreStatus
    let effectiveColorScheme: ColorScheme
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: iconName)
                .font(.montserratBold(size: 15))
                .foregroundStyle(.primary)

            if message.isEmpty == false {
                Text(message)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.secondary)
            }

            if status != .pending {
                Button("RETRY CHART RESTORE", action: onRetry)
                    .font(.montserratBold(size: 13))
                    .foregroundStyle(Color.ascendAccent)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            effectiveColorScheme == .dark
                ? Color.white.opacity(0.05)
                : Color.gray.opacity(0.06)
        )
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch status {
        case .pending:
            "RESTORING HEART RATE"
        case .retryPending:
            "HEART RATE WAITING"
        case .unavailable:
            "HEART RATE UNAVAILABLE"
        case .notNeeded, .ready:
            "HEART RATE"
        }
    }

    private var message: String {
        switch status {
        case .pending:
            "Restoring this workout's full chart on this device."
        case .retryPending:
            "Reconnect, then retry the saved chart."
        case .unavailable:
            "Ascend couldn't verify this workout's saved heart-rate series."
        case .notNeeded, .ready:
            ""
        }
    }

    private var iconName: String {
        status == .pending ? "arrow.triangle.2.circlepath" : "heart.slash"
    }
}
