import SwiftUI

struct BookmarkButton: View {
    let isSaved: Bool
    var action: () -> Void

    @State private var isAnimating = false

    var body: some View {
        Button {
            if !isSaved {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                    isAnimating = true
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isAnimating = false
                    }
                }
                HapticsManager.shared.trigger(.lightImpact)
            }

            action()
        } label: {
            ZStack {
                Color.clear

                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSaved ? .accent : .white.opacity(0.3))
                    .scaleEffect(isAnimating ? 1.3 : 1.0)
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack(spacing: 20) {
        BookmarkButton(isSaved: false) {}
        BookmarkButton(isSaved: true) {}
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
