import SwiftUI

/// A running event as a row in Home's sheet, in Today's Climb's shape: how long it has left, that
/// it is on, how much of it the climber has earned, and three of the things it gives. Tapping it
/// opens the event's page.
struct HomeEventCard: View {
    let event: UnlockEvent
    let showcase: [UnlockItem]
    let earned: Int
    let total: Int
    let daysLeft: Int
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(UnlockCopy.daysLeft(daysLeft))
                        .font(.montserratBold(size: 9.5))
                        .tracking(1.2)
                        .monospacedDigit()
                        .foregroundStyle(UnlockStyle.pumpkin)
                        .lineLimit(1)
                    Text("\(event.title) is on.")
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    Text(UnlockCopy.earnedLine(earned: earned, of: total))
                        .font(.montserratMedium(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 10)

                items
                    .padding(.trailing, 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.trailing, 12)
            }
            .frame(minHeight: 104)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [UnlockStyle.pumpkin.opacity(0.12), UnlockStyle.pumpkin.opacity(0.04)], startPoint: .leading, endPoint: .trailing))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(UnlockStyle.pumpkin.opacity(0.55), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title) is on. \(UnlockCopy.daysLeft(daysLeft).lowercased()).")
        .accessibilityValue(UnlockCopy.earnedLine(earned: earned, of: total))
        .accessibilityHint("Opens \(event.title)")
    }

    /// The middle item is larger, raised, and in front of its neighbours.
    private var items: some View {
        HStack(alignment: .bottom, spacing: -8) {
            ForEach(Array(showcase.enumerated()), id: \.element.id) { index, item in
                let isMiddle = index == 1
                Image(item.shape.thumbnailName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: isMiddle ? 52 : 44, height: isMiddle ? 52 : 44)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 6)
                    .offset(y: isMiddle ? -6 : 0)
                    .zIndex(isMiddle ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }
}
