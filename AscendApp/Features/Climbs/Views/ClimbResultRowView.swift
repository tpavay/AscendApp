import SwiftUI

struct ClimbResultRowView: View {
    let climb: Climb
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 12) {
            ClimbArtworkView(climb: climb, variant: .thumb)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(climb.name)
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accent)
                    }
                }

                Text(climb.displayLocation)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(climb.referenceStepCount.formatted())
                    .font(.montserratBold(size: 13))
                    .foregroundStyle(climb.tier.color)

                Text("steps")
                    .font(.montserratMedium(size: 9))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}

#Preview {
    VStack {
        ClimbResultRowView(climb: .preview, isCompleted: false)
        ClimbResultRowView(climb: .preview, isCompleted: true)
    }
    .padding()
    .background(Color.black)
}
