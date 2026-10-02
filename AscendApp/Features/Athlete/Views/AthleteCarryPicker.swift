import SwiftUI

/// The editor's unlocks row: every item of every event that has opened, the ones the climber has
/// earned ready to wear, the rest locked with what earns them. One item per slot: tapping an
/// earned item puts it on, tapping what is on takes it off.
struct AthleteCarryPicker: View {
    let progress: [UnlockEventProgress]
    let earned: Set<AthleteGear>
    @Binding var look: AthleteLook

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(progress, id: \.event.id) { event in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(event.event.title.uppercased())
                            .font(.montserratBold(size: 11))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.48))
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Text(UnlockCopy.tally(event))
                            .font(.montserratMedium(size: 11))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(event.items, id: \.id) { item in
                                tile(item, in: event.event)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private func tile(_ item: UnlockItem, in event: UnlockEvent) -> some View {
        let isWorn = look.wearing(item.shape.slot) == item.shape
        let isEarned = earned.contains(item.shape) || isWorn
        return Button {
            guard isEarned else { return }
            withAnimation(.smooth(duration: 0.18)) {
                if isWorn {
                    look.unequip(item.shape.slot)
                } else {
                    look.equip(item.shape)
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(item.shape.thumbnailName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .saturation(isEarned ? 1 : 0)
                    .opacity(isEarned ? 1 : 0.4)
                    .overlay(alignment: .bottomTrailing) {
                        if !isEarned {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                Text(item.shape.title.uppercased())
                    .font(.montserratBold(size: 10))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(isEarned ? 0.92 : 0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(isWorn ? "ON" : (isEarned ? "EARNED" : UnlockCopy.requirement(item, in: event)))
                    .font(.montserratMedium(size: 9))
                    .foregroundStyle(isEarned ? Color.accent : .white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 84)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isWorn ? Color.accent : .white.opacity(0.1), lineWidth: isWorn ? 2 : 1)
                    }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.shape.title)
        .accessibilityValue(isWorn ? "On" : (isEarned ? "Earned" : "Locked. \(UnlockCopy.requirement(item, in: event)) in \(event.monthName)"))
        .accessibilityAddTraits(isWorn ? .isSelected : [])
    }
}

extension AthleteGear {
    /// The item's picture in the asset catalogue, photographed from the real model.
    var thumbnailName: String { "Gear/\(rawValue)" }
}

/// The words unlock surfaces use, in one place so the editor and the unlock moment agree.
enum UnlockCopy {
    /// "10 CLIMBS", "25K STEPS", "EVERY DAY".
    static func requirement(_ item: UnlockItem, in event: UnlockEvent? = nil) -> String {
        let threshold = item.earn.threshold
        switch item.earn.metric {
        case .visits: return "OPEN ASCEND"
        case .climbs: return threshold == 1 ? "1 CLIMB" : "\(threshold) CLIMBS"
        case .days:
            if let event, threshold == event.dayCount() { return "EVERY DAY" }
            return threshold == 1 ? "1 DAY" : "\(threshold) DAYS"
        case .steps: return "\(compact(threshold)) STEPS"
        }
    }

    /// "4 CLIMBS · 12,400 STEPS".
    static func tally(_ progress: UnlockEventProgress) -> String {
        let climbs = progress.climbs == 1 ? "1 CLIMB" : "\(progress.climbs) CLIMBS"
        return "\(climbs) · \(progress.steps.formatted()) STEPS"
    }

    /// What is left on each ladder: "2 more climbs to the Ghost Pumpkin".
    static func nextLines(_ progress: UnlockEventProgress) -> [String] {
        progress.nextItems.map { next in
            let amount = switch next.item.earn.metric {
            case .visits: "Open Ascend"
            case .climbs: next.remaining == 1 ? "1 more climb" : "\(next.remaining) more climbs"
            case .days: next.remaining == 1 ? "1 more day climbing" : "\(next.remaining) more days climbing"
            case .steps: "\(next.remaining.formatted()) more steps"
            }
            return "\(amount) to the \(next.item.shape.title)"
        }
    }

    static func compact(_ value: Int) -> String {
        value >= 1_000 && value % 1_000 == 0 ? "\(value / 1_000)K" : value.formatted()
    }
}
