//
//  DraggableDetailSheet.swift
//  AscendApp
//
//  Created by Tyler Pavay on 1/15/26.
//

import SwiftUI

/// A custom draggable sheet that overlays content with three snap positions
struct DraggableDetailSheet<Content: View>: View {
    @Binding var position: SheetPosition
    /// Binding to expose current offset for smooth hero animation
    @Binding var currentOffset: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    /// Current drag offset during gesture
    @GestureState private var dragOffset: CGFloat = 0

    let content: () -> Content

    init(position: Binding<SheetPosition>, currentOffset: Binding<CGFloat> = .constant(0), @ViewBuilder content: @escaping () -> Content) {
        self._position = position
        self._currentOffset = currentOffset
        self.content = content
    }

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        GeometryReader { geometry in
            let baseOffset = position.offset(in: geometry)
            let totalOffset = baseOffset + dragOffset
            let minOffset: CGFloat = 0
            let maxOffset = geometry.size.height * 0.85
            let clampedOffset = min(max(totalOffset, minOffset), maxOffset)

            VStack(spacing: 0) {
                // Drag handle area - always draggable
                dragHandleArea

                // Sheet content
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(sheetBackground)
            .clipShape(RoundedCorner(radius: 16, corners: [.topLeft, .topRight]))
            .offset(y: clampedOffset)
            .conditionalGesture(enabled: position != .expanded, gesture: dragGesture(in: geometry))
            .animation(dragOffset == 0 ? .spring(response: 0.35, dampingFraction: 0.8) : nil, value: position)
            .onChange(of: clampedOffset) { _, newOffset in
                // Update currentOffset for hero animation during drag
                currentOffset = dragOffset != 0 ? newOffset : 0
            }
        }
    }

    // MARK: - View Components

    /// Larger drag handle area for easier grabbing
    private var dragHandleArea: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.3) : Color.gray.opacity(0.4))
                .frame(width: 36, height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .contentShape(Rectangle())
    }

    private var sheetBackground: some View {
        effectiveColorScheme == .dark ? Color.black : Color.white
    }

    // MARK: - Gestures

    private func dragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height - value.translation.height

                let targetPosition = SheetPosition.targetPosition(
                    from: position,
                    dragOffset: value.translation.height,
                    velocity: velocity,
                    in: geometry
                )

                // Haptic feedback on position change
                if targetPosition != position {
                    HapticsManager.shared.trigger(.selection)
                }

                position = targetPosition
            }
    }
}

/// Helper shape for rounding specific corners
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

/// Extension to conditionally apply a gesture
extension View {
    @ViewBuilder
    func conditionalGesture<G: Gesture>(enabled: Bool, gesture: G) -> some View {
        if enabled {
            self.gesture(gesture)
        } else {
            self
        }
    }
}
