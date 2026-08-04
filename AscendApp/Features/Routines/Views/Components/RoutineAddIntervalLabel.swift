import SwiftUI

/// The drawn face of the + row below the timeline. Split from the button so the appearance
/// has one definition - the snapshot evidence renders this view rather than a copy of it.
struct RoutineAddIntervalLabel: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))

            Text("Add Interval")
                .font(.montserratSemiBold(size: 16))
        }
        .foregroundStyle(Color.accent)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    Color.accent.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
        )
    }
}

#Preview {
    RoutineAddIntervalLabel()
        .padding(20)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
