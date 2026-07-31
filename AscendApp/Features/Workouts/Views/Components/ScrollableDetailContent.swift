//
//  ScrollableDetailContent.swift
//  AscendApp
//
//  Created by Tyler Pavay on 1/15/26.
//

import SwiftUI

/// A ScrollView wrapper that coordinates with the sheet position.
/// When scrolled to top and user pulls down, it triggers sheet collapse.
struct ScrollableDetailContent<Content: View>: View {
    @Binding var sheetPosition: SheetPosition
    let content: () -> Content

    @State private var isAtTop: Bool = true

    private let scrollToCollapseThreshold: CGFloat = 50

    /// Tolerance for bounce, so a rubber-banded top still counts as the top.
    private let atTopTolerance: CGFloat = 5

    var body: some View {
        ScrollView {
            content()
        }
        .scrollDisabled(sheetPosition != .expanded)  // Only scroll when fully expanded
        // Only the at-top verdict matters here, so deriving it inside the closure
        // means the action fires when the answer flips rather than on every tick.
        // The preference-key plumbing this replaces republished the raw offset every
        // frame and stored it in state nothing read.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top <= atTopTolerance
        } action: { _, atTop in
            isAtTop = atTop
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
