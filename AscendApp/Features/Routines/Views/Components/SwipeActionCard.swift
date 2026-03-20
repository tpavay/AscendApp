import SwiftUI

struct SwipeActionCard<Content: View, ActionContent: View>: View {
    var actionWidth: CGFloat = 88
    @ViewBuilder var actionContent: () -> ActionContent
    @ViewBuilder var content: () -> Content

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var restingOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            actionContent()
                .frame(width: actionWidth)
                .clipShape(.rect(cornerRadius: 16))

            content()
                .offset(x: effectiveOffset)
                .contentShape(.rect(cornerRadius: 16))
                .gesture(dragGesture)
                .onTapGesture {
                    if restingOffset != 0 {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                            restingOffset = 0
                        }
                    }
                }
        }
        .clipShape(.rect(cornerRadius: 16))
    }

    private var effectiveOffset: CGFloat {
        let offset = restingOffset + dragTranslation
        return min(0, max(-actionWidth, offset))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragTranslation) { value, state, _ in
                let translation = value.translation.width
                if translation < 0 || restingOffset < 0 {
                    state = translation
                }
            }
            .onEnded { value in
                let proposedOffset = restingOffset + value.translation.width
                let shouldOpen = proposedOffset < -(actionWidth * 0.45)

                withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                    restingOffset = shouldOpen ? -actionWidth : 0
                }
            }
    }
}

#Preview {
    SwipeActionCard(
        actionContent: {
            Button("Delete") {}
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.red)
                .foregroundStyle(.white)
        },
        content: {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 120)
        }
    )
    .padding(20)
    .preferredColorScheme(.dark)
}
