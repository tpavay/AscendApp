import SwiftUI

/// The gear a climber can put on, inside Your Athlete: a row per place on the athlete, every item
/// shown whether earned or not. An earned item goes on the athlete above the moment it is tapped,
/// and comes off when tapped again; a locked one opens a line under its row with what it takes and
/// how far the climber is. Nothing is kept until SAVE ATHLETE.
struct AthleteGearRows: View {
    /// One item and the event progress that earns it.
    struct Entry: Identifiable, Equatable {
        let item: UnlockItem
        let progress: UnlockEventProgress
        var id: String { item.id }
    }

    /// The rows, in the order they read, and the slots each one holds.
    enum Row: String, CaseIterable, Identifiable {
        case carried, head, kit, feet

        var id: String { rawValue }
        var title: String { rawValue.uppercased() }

        var slots: [AthleteGear.Slot] {
            switch self {
            case .carried: [.carry]
            case .head: [.head]
            case .kit: [.costume, .shorts]
            case .feet: [.trainers]
            }
        }
    }

    let entries: [Entry]
    let owned: Set<AthleteGear>
    let new: Set<AthleteGear>
    let wearing: [AthleteGear]
    let onWear: (AthleteGear) -> Void
    let onTakeOff: (AthleteGear) -> Void

    @State private var opened: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Row.allCases) { row in
                // What the climber owns first, ready to tap; then what they are working toward.
                let inRow = entries.filter { row.slots.contains($0.item.shape.slot) }
                let cells = inRow.filter { owned.contains($0.item.shape) } + inRow.filter { !owned.contains($0.item.shape) }
                if !cells.isEmpty {
                    rowView(row, cells: cells)
                }
            }
        }
    }

    private func rowView(_ row: Row, cells: [Entry]) -> some View {
        let ownedCount = cells.filter { owned.contains($0.item.shape) }.count
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(.montserratBold(size: 11))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.48))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(ownedCount) owned")
                    .font(.montserratBold(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.32))
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(cells) { entry in
                        cell(entry)
                    }
                }
                // Room for the worn cell's border, which a scroll view would otherwise clip.
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            if let open = cells.first(where: { $0.id == opened }) {
                lockedLine(open)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func cell(_ entry: Entry) -> some View {
        let shape = entry.item.shape
        let isOwned = owned.contains(shape)
        let isWorn = wearing.contains(shape)
        let counted = UnlockItemProgress(item: entry.item, progress: entry.progress)
        let cellShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            withAnimation(.smooth(duration: 0.2)) {
                if !isOwned {
                    opened = opened == entry.id ? nil : entry.id
                } else if isWorn {
                    opened = nil
                    onTakeOff(shape)
                } else {
                    opened = nil
                    onWear(shape)
                }
            }
        } label: {
            Image(shape.thumbnailName)
                .resizable()
                .scaledToFit()
                .frame(width: 62, height: 62)
                .shadow(color: .black.opacity(0.55), radius: 4, y: 6)
                .opacity(isOwned ? 1 : 0.35)
                .saturation(isOwned ? 1 : 0.4)
                .frame(width: 76, height: 76)
                .background(
                    cellShape.fill(
                        RadialGradient(
                            colors: [isWorn ? Color.accent.opacity(0.28) : Color(hex: "#1C1F24"), Color(hex: "#0F1113")],
                            center: UnitPoint(x: 0.5, y: 0.55),
                            startRadius: 0,
                            endRadius: 43
                        )
                    )
                )
                .overlay(alignment: .topLeading) {
                    if isWorn {
                        UnlockTag(text: "ON", fill: Color.accent, ink: UnlockStyle.limeInk).padding(5)
                    } else if new.contains(shape) {
                        UnlockTag(text: "NEW", fill: UnlockStyle.pumpkin, ink: UnlockStyle.pumpkinInk).padding(5)
                    }
                }
                .overlay(alignment: .bottom) {
                    if !isOwned, let counted {
                        UnlockProgressBar(fraction: counted.fraction, height: 3, fill: AnyShapeStyle(Color.accent), minimum: 0.04)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 7)
                    }
                }
                .clipShape(cellShape)
                .overlay(cellShape.strokeBorder(isWorn ? Color.accent : .white.opacity(0.07), lineWidth: isWorn ? 2 : 1))
                .contentShape(cellShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shape.title)
        .accessibilityValue(isWorn ? "On your athlete" : isOwned ? (new.contains(shape) ? "Earned, new" : "Earned") : "Locked")
        .accessibilityHint(isWorn ? "Takes it off" : isOwned ? "Puts it on your athlete" : "Shows what it takes")
        .accessibilityAddTraits(isWorn ? .isSelected : [])
    }

    private func lockedLine(_ entry: Entry) -> some View {
        let counted = UnlockItemProgress(item: entry.item, progress: entry.progress)
        let rule = UnlockCopy.rule(entry.item, in: entry.progress.event)
        let detail = counted.map { "\(rule) · \($0.have.formatted()) of \($0.need.formatted()) \($0.unit)" } ?? rule
        return HStack(spacing: 12) {
            Image(entry.item.shape.thumbnailName)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .opacity(0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.shape.title)
                    .font(.montserratBold(size: 13))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.montserratSemiBold(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
                if let counted {
                    UnlockProgressBar(fraction: counted.fraction, height: 4, fill: AnyShapeStyle(Color.accent), minimum: 0.02)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}
