import SwiftUI

struct RoutineHorizontalRail<Content: View>: View {
    let routines: [Routine]
    var spacing: CGFloat = 12
    @ViewBuilder var content: (Routine) -> Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(routines) { routine in
                    content(routine)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    RoutineHorizontalRail(routines: Array(BuiltInRoutines.previewTemplates.prefix(3))) { routine in
        RoutineThumbnailCard(routine: routine)
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
