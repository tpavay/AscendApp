import SwiftUI

/// The first open during an event: the item everybody gets for showing up, on the climber's own
/// athlete, and the ladder of what climbing this month earns. Everything it says comes from the
/// catalogue, so the next month's event reuses it with no new screen.
struct UnlockEventIntroView: View {
    let event: UnlockEvent
    let items: [UnlockItem]
    let look: AthleteLook
    let earned: Set<AthleteGear>
    /// Carries the visit item and closes.
    let onCarry: (AthleteGear) -> Void
    let onClose: () -> Void

    private var visitItem: UnlockItem? {
        items.first { $0.earn.metric == .visits }
    }

    private var ladder: [UnlockItem] {
        items.filter { $0.earn.metric != .visits }
            .sorted { ($0.earn.metric == .climbs ? 0 : 1, $0.earn.threshold) < ($1.earn.metric == .climbs ? 0 : 1, $1.earn.threshold) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("\(event.monthName.uppercased()) ON ASCEND MOUNTAIN")
                            .font(.montserratBold(size: 11))
                            .tracking(1.6)
                            .foregroundStyle(Color.accent)
                        Text("\(event.title.uppercased()) IS ON")
                            .font(.montserratBold(size: 30))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.top, 28)

                    if let visitItem {
                        AthletePreviewView(look: carrying(visitItem.shape), framing: .fullBody)
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                            .background(RadialGradient(colors: [Color(red: 0.2, green: 0.1, blue: 0.02), .black],
                                                       center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: 220))
                        VStack(spacing: 6) {
                            Text("YOUR \(visitItem.shape.title.uppercased()) IS IN")
                                .font(.montserratBold(size: 18))
                                .foregroundStyle(.white)
                            Text("Opening Ascend in \(event.monthName) earned it. Carry it up the mountain.")
                                .font(.montserratMedium(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 24)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("CLIMB IN \(event.monthName.uppercased()) TO EARN MORE")
                            .font(.montserratBold(size: 11))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.5))
                        ForEach(ladder, id: \.id) { item in
                            row(item)
                        }
                        Text(endsLine)
                            .font(.montserratMedium(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                }
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 8) {
                if let visitItem {
                    Button {
                        onCarry(visitItem.shape)
                    } label: {
                        Text("CARRY IT")
                            .font(.montserratBold(size: 14))
                            .tracking(1.1)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accent))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    onClose()
                } label: {
                    Text("NOT NOW")
                        .font(.montserratBold(size: 13))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .trackOnce(screen: .unlockEventIntro)
    }

    private func carrying(_ shape: AthleteGear) -> AthleteLook {
        var look = look
        look.carry = shape
        return look
    }

    private var endsLine: String {
        let calendar = Calendar.current
        guard let end = event.interval(in: calendar)?.end,
              let lastDay = calendar.date(byAdding: .day, value: -1, to: end) else { return "" }
        return "Ends \(lastDay.formatted(.dateTime.month(.wide).day())). Everything you earn is yours to keep."
    }

    private func row(_ item: UnlockItem) -> some View {
        let isEarned = earned.contains(item.shape)
        return HStack(spacing: 14) {
            Image(item.shape.thumbnailName)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.shape.title.uppercased())
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.white)
                Text(UnlockCopy.requirement(item))
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 8)
            if isEarned {
                Text("EARNED")
                    .font(.montserratBold(size: 11))
                    .tracking(1)
                    .foregroundStyle(Color.accent)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isEarned ? "Earned" : "Locked")
    }
}
