import SwiftUI

struct HomeLogWorkoutButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Workout")
                        .font(.montserratBold(size: 18))

                    Text("Manual, routine, import")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.black.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(10)
                    .background(Circle().fill(.black.opacity(0.1)))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.accent)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open workout logging options")
    }
}
