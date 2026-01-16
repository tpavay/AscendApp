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
            pullToCollapseGesture,
            including: sheetPosition == .expanded && isAtTop ? .all : .subviews
        )
    }

    /// Gesture that collapses the sheet when pulling down from the top while expanded
    private var pullToCollapseGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                // Only trigger collapse when expanded, at top, and pulling down
                if sheetPosition == .expanded && isAtTop && value.translation.height > scrollToCollapseThreshold {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        sheetPosition = .middle
                    }
                    HapticsManager.shared.trigger(.selection)
                }
            }
    }
}
