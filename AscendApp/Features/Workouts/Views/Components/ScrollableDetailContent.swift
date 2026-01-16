//
//  ScrollableDetailContent.swift
//  AscendApp
//
//  Created by Tyler Pavay on 1/15/26.
//

import SwiftUI

/// Preference key to track scroll offset
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A ScrollView wrapper that coordinates with the sheet position.
/// When scrolled to top and user pulls down, it triggers sheet collapse.
struct ScrollableDetailContent<Content: View>: View {
    @Binding var sheetPosition: SheetPosition
    let content: () -> Content

    @State private var scrollOffset: CGFloat = 0
    @State private var isAtTop: Bool = true
    @State private var isDraggingFromTop: Bool = false

    private let scrollToCollapseThreshold: CGFloat = 50

    var body: some View {
        ScrollView {
            content()
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).origin.y
                            )
                    }
                )
        }
        .scrollDisabled(sheetPosition != .expanded)  // Only scroll when fully expanded
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            scrollOffset = offset
            isAtTop = offset >= -5  // Small tolerance for bounce
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    // Only activate pull-to-collapse when expanded and at top
                    if sheetPosition == .expanded && isAtTop && value.translation.height > 0 {
                        isDraggingFromTop = true
                    }
                }
                .onEnded { value in
                    if isDraggingFromTop && value.translation.height > scrollToCollapseThreshold {
                        // Collapse sheet to show photo
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            sheetPosition = .middle
                        }
                        HapticsManager.shared.trigger(.selection)
                    }
                    isDraggingFromTop = false
                }
        )
    }
}
