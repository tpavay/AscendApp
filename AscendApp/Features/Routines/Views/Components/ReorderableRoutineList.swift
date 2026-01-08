import SwiftUI

struct ReorderableRoutineList: View {
    @State private var routines: [Routine]
    let onRoutineTapped: (Routine) -> Void
    let onReorder: ([Routine]) -> Void

    init(initialRoutines: [Routine], onRoutineTapped: @escaping (Routine) -> Void, onReorder: @escaping ([Routine]) -> Void) {
        self._routines = State(initialValue: initialRoutines)
        self.onRoutineTapped = onRoutineTapped
        self.onReorder = onReorder
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    // Approximate height per card
    private let cardHeight: CGFloat = 100
    private let rowVerticalPadding: CGFloat = 12

    private var listHeight: CGFloat {
        CGFloat(routines.count) * (cardHeight + rowVerticalPadding)
    }

    var body: some View {
        List($routines, id: \.id, editActions: .move) { $routine in
            RoutineCard(routine: routine) {
                onRoutineTapped(routine)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(height: listHeight)
        .onChange(of: routines) { _, newValue in
            // Update order values when list changes
            for (index, routine) in newValue.enumerated() {
                routine.order = index
            }
            onReorder(newValue)
        }
    }
}

#Preview {
    ReorderableRoutineList(
        initialRoutines: [],
        onRoutineTapped: { _ in },
        onReorder: { _ in }
    )
    .padding(20)
}
