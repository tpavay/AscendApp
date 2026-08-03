import SwiftUI

/// The drawn face of the step-type row. Split from `RoutineStepTypeControl` so the row's
/// appearance can be rendered on its own - a `Menu` cannot be flattened by `ImageRenderer`,
/// which is how the rest of this screen is checked visually.
struct RoutineStepTypeRowLabel: View {
    let stepType: RoutineStepTypeOption

    var body: some View {
        HStack(spacing: 12) {
            Text("Step".uppercased())
                .font(.montserratBold(size: 10))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.32))

            Spacer(minLength: 12)

            Text(stepType.displayName)
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(.white)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.customGray)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.jetLighter.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        RoutineStepTypeRowLabel(stepType: .standard)
        RoutineStepTypeRowLabel(stepType: .faceRight)
    }
    .padding(20)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
