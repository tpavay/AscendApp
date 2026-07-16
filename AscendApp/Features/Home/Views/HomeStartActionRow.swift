import SwiftUI

struct HomeStartActionRow: View {
    let action: HomeStartAction
    let onSelect: (HomeStartAction) -> Void

    var body: some View {
        Button {
            onSelect(action)
        } label: {
            HStack(spacing: 14) {
                AppIcon(token: action.iconToken, pointSize: 24, weight: .semibold)
                    .foregroundStyle(Color.accent)
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accent.opacity(0.13))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accent.opacity(0.18), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(action.title.uppercased())
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(action.subtitle)
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.36))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle)
    }
}

#Preview {
    VStack(spacing: 10) {
        ForEach(HomeStartAction.allCases, id: \.self) { action in
            HomeStartActionRow(action: action) { _ in }
        }
    }
    .padding()
    .background(Color.black)
}
