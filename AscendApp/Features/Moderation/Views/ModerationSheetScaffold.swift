import SwiftUI

/// Keeps the decision controls reachable when Dynamic Type or a compact sheet
/// leaves less vertical room than the moderation reason list needs.
struct ModerationSheetScaffold<Content: View, Footer: View>: View {
    let title: String
    let message: String
    let content: Content
    let footer: Footer

    init(
        title: String,
        message: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.message = message
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()
                .overlay(.white.opacity(0.08))

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)

            Divider()
                .overlay(.white.opacity(0.08))

            footer
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .appSheetBackground()
    }
}
