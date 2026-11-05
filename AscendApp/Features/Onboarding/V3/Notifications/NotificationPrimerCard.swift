import SwiftUI

/// A sample notification as iOS draws it: the app tile, a title with its time, the body, and the
/// gear picture when the notification carries one.
struct NotificationPrimerCard: View {
    let example: NotificationPrimerExample
    /// The smallest phones tighten the card's vertical padding.
    var isCompact = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var whenSize: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 13

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("AppIconInternalAccent")
                .resizable()
                .scaledToFit()
                .padding(9)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(hex: "2A2A2A"), lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                // At an accessibility size the time label takes its own line: beside the title it
                // left the title a column so narrow that a word broke in the middle.
                let layout = dynamicTypeSize.isAccessibilitySize ?
                    AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) :
                    AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

                layout {
                    Text(example.title)
                        .font(.custom("Montserrat-Bold", fixedSize: titleSize))
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 0)
                    }

                    Text(example.when)
                        .font(.custom("Montserrat-Medium", fixedSize: whenSize))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                Text(example.body)
                    .font(.custom("Montserrat-Medium", fixedSize: bodySize))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineSpacing(bodySize * 0.12)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let thumbnailName = example.thumbnailName, !dynamicTypeSize.isAccessibilitySize {
                Image(thumbnailName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompact ? 9 : 13)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(white: 0.16, opacity: 0.62))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example notification. \(example.title), \(example.when). \(example.body)")
    }
}
