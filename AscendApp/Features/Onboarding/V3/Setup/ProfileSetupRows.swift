import SwiftUI

/// A group of tappable rows: a label, its value or "Not set", and a chevron, divided by hairlines.
struct ProfileSetupRows: View {
    struct Row: Identifiable {
        let title: String
        let value: String?
        let action: () -> Void

        var id: String { title }
    }

    let rows: [Row]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button(action: row.action) {
                    HStack(spacing: 10) {
                        Text(row.title)
                            .font(.custom("Montserrat-Bold", size: 15, relativeTo: .body))
                            .foregroundStyle(.white)

                        Spacer(minLength: 0)

                        Text(row.value ?? "Not set")
                            .font(.custom(row.value == nil ? "Montserrat-SemiBold" : "Montserrat-ExtraBold", size: 14.5, relativeTo: .body))
                            .foregroundStyle(row.value == nil ? OnboardingV3Palette.placeholder : Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(OnboardingV3Palette.placeholder)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.title)
                .accessibilityValue(row.value ?? "Not set")
                .accessibilityAddTraits(.isButton)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(OnboardingV3Palette.cardBorder)
                        .frame(height: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(OnboardingV3Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OnboardingV3Palette.fieldBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
