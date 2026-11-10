import SwiftUI

/// What every manage-sheet row leads with: the tinted icon badge, the title, and a line of detail
/// when the row needs one.
struct IntegrationManageRowLabel: View {
    let systemImage: String
    let title: String
    let subtitle: String?
    let iconTint: Color
    let titleColor: Color

    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        iconTint: Color = .accent,
        titleColor: Color = .white
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.iconTint = iconTint
        self.titleColor = titleColor
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconTint.opacity(0.14))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(titleColor)

                if let subtitle {
                    Text(subtitle)
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
