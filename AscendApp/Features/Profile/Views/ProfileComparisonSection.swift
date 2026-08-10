import SwiftUI

struct ProfileComparisonSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.montserratBold(size: 12))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .tracking(3)

            content
        }
    }
}
