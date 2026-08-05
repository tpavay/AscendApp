import SwiftUI

struct ProfileValueRow<Destination: View>: View {
    let icon: AppIconToken
    let title: String
    let value: String
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 16) {
                AppIcon(token: icon, pointSize: 20, weight: .medium)
                    .foregroundStyle(.accent)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.montserratMedium)
                    .foregroundStyle(.white)

                Spacer(minLength: 12)

                Text(value)
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)

                AppIcon(token: .disclosureChevronRight, pointSize: 14, weight: .medium)
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint("Opens editor")
    }
}
