import SwiftUI

struct ProfileCardSurfaceView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(ProfileVisualStyle.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ProfileVisualStyle.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
