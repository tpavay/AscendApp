import SwiftUI

struct StatusBannerView: View {
    enum Style {
        case warning
        case success
        case error
    }

    @Environment(\.colorScheme) private var colorScheme

    let message: String
    let style: Style

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)

            Text(message)
                .font(.montserratRegular(size: 13))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
        )
    }

    private var iconName: String {
        switch style {
        case .warning:
            return "wifi.slash"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch style {
        case .warning:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .warning:
            return colorScheme == .dark ? Color.orange.opacity(0.15) : Color.orange.opacity(0.1)
        case .success:
            return colorScheme == .dark ? Color.green.opacity(0.18) : Color.green.opacity(0.12)
        case .error:
            return colorScheme == .dark ? Color.red.opacity(0.2) : Color.red.opacity(0.1)
        }
    }
}
