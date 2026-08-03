import SwiftUI

struct LiveHeartRateStatusChip: View {
    let status: LiveHeartRateStatus

    private var tint: Color {
        switch status {
        case .connected(_, let zone):
            return zone.color
        case .connecting, .reconnecting, .signalLost, .failed:
            return .white.opacity(0.52)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)

            Text(status.displayText)
                .font(.montserratBold(size: status.isConnectedReading ? 13 : 10))
                .monospacedDigit()
                .foregroundStyle(status.isConnectedReading ? .white : .white.opacity(0.62))
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(tint.opacity(0.16))
        )
        .animation(.smooth(duration: 0.3), value: tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityText)
    }

    private var systemImage: String {
        switch status {
        case .connecting, .reconnecting:
            return "dot.radiowaves.left.and.right"
        case .failed:
            return "heart.slash.fill"
        case .connected, .signalLost:
            return "heart.fill"
        }
    }
}

private extension LiveHeartRateStatus {
    var isConnectedReading: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}
