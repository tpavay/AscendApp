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
    @State private var dragOffset: CGFloat = 0

    /// Whether the sheet is being dragged
    @State private var isDragging: Bool = false

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
            let offset = calculateOffset(in: geometry)

            VStack(spacing: 0) {
                // Drag handle
                dragHandle
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Sheet content
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(sheetBackground)
            .clipShape(RoundedCorner(radius: 16, corners: [.topLeft, .topRight]))
            .offset(y: offset)
            .gesture(dragGesture(in: geometry))
            .animation(isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: position)
            .onChange(of: isDragging) { _, dragging in
                if !dragging {
                    // Reset currentOffset to 0 when drag ends so hero uses position-based animation
                    currentOffset = 0
                }
            }
        }
    }

    // MARK: - View Components

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.3) : Color.gray.opacity(0.4))
            .frame(width: 36, height: 5)
    }

    private var sheetBackground: some View {
        effectiveColorScheme == .dark ? Color.black : Color.white
    }

    // MARK: - Calculations

    private func calculateOffset(in geometry: GeometryProxy) -> CGFloat {
        let baseOffset = position.offset(in: geometry)
        let totalOffset = baseOffset + dragOffset

        // Clamp to prevent dragging beyond bounds
        let minOffset: CGFloat = 0  // Fully expanded
        let maxOffset = geometry.size.height * 0.85  // Don't go below screen

        let clampedOffset = min(max(totalOffset, minOffset), maxOffset)

        // Update the binding so hero can animate smoothly with drag
        DispatchQueue.main.async {
            currentOffset = clampedOffset
        }

        return clampedOffset
    }

    // MARK: - Gestures

    private func dragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation.height
            }
            .onEnded { value in
                isDragging = false

                let velocity = value.predictedEndTranslation.height - value.translation.height

                let targetPosition = SheetPosition.targetPosition(
                    from: position,
                    dragOffset: dragOffset,
                    velocity: velocity,
                    in: geometry
                )

                // Haptic feedback on position change
                if targetPosition != position {
                    HapticsManager.shared.trigger(.selection)
                }

                position = targetPosition
                dragOffset = 0
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
