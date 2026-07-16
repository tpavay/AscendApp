#if DEBUG
import SwiftUI

struct JourneySelectorCard: View {
    let journey: JourneyPrototype
    let completedClimbIds: Set<String>
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(journey.title)
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(journey.subtitle.uppercased())
                        .font(.montserratSemiBold(size: 9))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer()

                Text(journey.progressText(in: completedClimbIds))
                    .font(.montserratBold(size: 11))
                    .foregroundStyle(isSelected ? .black.opacity(0.86) : journey.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(isSelected ? journey.accent : .white.opacity(0.08), in: Capsule())
            }

            Text(journey.thesis)
                .font(.montserratMedium(size: 12))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.1))
                    Capsule()
                        .fill(journey.accent)
                        .frame(width: proxy.size.width * progressFraction)
                }
            }
            .frame(height: 5)
        }
        .frame(width: 238, alignment: .leading)
        .padding(14)
        .background(isSelected ? .white.opacity(0.11) : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? journey.accent.opacity(0.9) : .white.opacity(0.12), lineWidth: 1)
        }
    }

    private var progressFraction: CGFloat {
        guard journey.climbs.isEmpty == false else { return 0 }
        return CGFloat(journey.completedPrefixCount(in: completedClimbIds)) / CGFloat(journey.climbs.count)
    }
}
#endif
