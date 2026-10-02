import SwiftData
import SwiftUI

/// The Locker: everything a climber can unlock, by where it goes, with what they have earned
/// ready to wear and what they have not showing how far they are. Wearing something here is a
/// change to the athlete, kept when they save.
struct LockerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var unlocks = UnlockStore.shared
    @State private var model: AthleteEditorModel
    @State private var progress: [UnlockEventProgress] = []
    @State private var tab: Tab = .carry
    /// The cards turned over to show how they are earned.
    @State private var flipped: Set<String> = []
    private let store: AthleteLookStore
    /// The signed-in climber.
    let userId: String?

    /// The Locker's tabs: slots that read as one place on the athlete share a tab.
    enum Tab: String, CaseIterable, Identifiable {
        case carry, head, costume, kit, feet

        var id: String { rawValue }
        var title: String { rawValue.uppercased() }

        var slots: [AthleteGear.Slot] {
            switch self {
            case .carry: [.carry]
            case .head: [.head]
            case .costume: [.costume]
            case .kit: [.shorts]
            case .feet: [.trainers]
            }
        }
    }

    /// Opens on `tab`, or on the tab of `revealing` with that item turned over to show how it
    /// is earned.
    init(userId: String?, opening tab: Tab = .carry, revealing item: AthleteGear? = nil, store: AthleteLookStore = .shared, unlocks: UnlockStore = .shared) {
        self.userId = userId
        self.store = store
        _unlocks = State(initialValue: unlocks)
        _tab = State(initialValue: item.flatMap { item in Tab.allCases.first { $0.slots.contains(item.slot) } } ?? tab)
        _flipped = State(initialValue: item.map { [$0.rawValue] } ?? [])
        _model = State(initialValue: AthleteEditorModel(look: store.current))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        stage
                        tabs
                        grid
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .onChange(of: progress.isEmpty) { _, isEmpty in
                    // An item opened turned over is brought into view once the cards exist.
                    guard !isEmpty, let revealed = flipped.first else { return }
                    withAnimation { reader.scrollTo(revealed, anchor: .center) }
                }
            }
            saveBar
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .trackOnce(screen: .locker)
        .task(id: userId) {
            guard let userId else { return }
            await unlocks.refreshCatalogIfNeeded()
            progress = unlocks.refresh(userId: userId, modelContext: modelContext)
            await model.loadSavedLook(userId: userId, from: store)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LOCKER")
                    .font(.montserratBold(size: 12))
                    .tracking(1.6)
                    .foregroundStyle(Color.accent)
                Text("Wear what you earned.")
                    .font(.montserratBold(size: 26))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.top, 20)
    }

    private var stage: some View {
        AthletePreviewView(look: model.draft, turns: false)
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(RadialGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.12), Color(red: 0.05, green: 0.05, blue: 0.06)],
                                         center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: 240))
            )
            .overlay(alignment: .bottomLeading) {
                let worn = model.draft.gear
                if !worn.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(worn) { item in
                                Text(item.title)
                                    .font(.montserratSemiBold(size: 11))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(.black.opacity(0.65)))
                            }
                        }
                        .padding(12)
                    }
                    .scrollIndicators(.hidden)
                }
            }
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases) { option in
                    let isSelected = option == tab
                    Button {
                        withAnimation(.smooth(duration: 0.18)) { tab = option }
                    } label: {
                        Text(option.title)
                            .font(.montserratBold(size: 12))
                            .tracking(0.8)
                            .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var grid: some View {
        let owned = unlocks.earned.union(model.draft.gear)
        let entries = progress.flatMap { event in unlocks.catalog.lockerItems(of: event.event, owned: owned).map { (event, $0) } }
            .filter { tab.slots.contains($0.1.shape.slot) }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(entries, id: \.1.id) { event, item in
                card(item, in: event)
                    .id(item.id)
            }
        }
        .overlay {
            if entries.isEmpty {
                Text("Nothing here yet. Climb this month to fill it.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, 40)
            }
        }
    }

    private func card(_ item: UnlockItem, in event: UnlockEventProgress) -> some View {
        let isWorn = model.draft.wearing(item.shape.slot) == item.shape
        let isEarned = unlocks.earned.union(model.draft.gear).contains(item.shape)
        let isFlipped = flipped.contains(item.id)
        return ZStack {
            front(item, in: event, isWorn: isWorn, isEarned: isEarned)
                .opacity(isFlipped ? 0 : 1)
            back(item, in: event, isEarned: isEarned)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .overlay(alignment: .topTrailing) {
            // Turns the card over to show how it is earned, whatever its state.
            Button {
                flip(item)
            } label: {
                Image(systemName: isFlipped ? "arrow.uturn.backward" : "info")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.black.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel(isFlipped ? "Show \(item.shape.title)" : "How \(item.shape.title) is earned")
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            // An earned card puts the item on or takes it off; a locked one turns over to say
            // what earns it.
            if isEarned && !isFlipped {
                guard model.isEditable else { return }
                withAnimation(.smooth(duration: 0.18)) {
                    if isWorn {
                        model.draft.unequip(item.shape.slot)
                    } else {
                        model.draft.equip(item.shape)
                    }
                }
            } else {
                flip(item)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.shape.title)
        .accessibilityValue(isWorn ? "Wearing" : (isEarned ? "Earned" : "Locked. \(requirementLine(item, event: event))"))
        .accessibilityAddTraits(isWorn ? [.isSelected, .isButton] : .isButton)
    }

    private func flip(_ item: UnlockItem) {
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            if flipped.contains(item.id) {
                flipped.remove(item.id)
            } else {
                flipped.insert(item.id)
            }
        }
    }

    private func front(_ item: UnlockItem, in event: UnlockEventProgress, isWorn: Bool, isEarned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.05))
                Image(item.shape.thumbnailName)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
                    .saturation(isEarned ? 1 : 0)
                    .opacity(isEarned ? 1 : 0.45)
                if isWorn {
                    badge("WEARING", fill: Color.accent)
                } else if !isEarned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(10)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            Text(item.shape.title)
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(isEarned ? (isWorn ? "Tap to take off" : "Tap to wear") : requirementLine(item, event: event))
                .font(.montserratMedium(size: 11))
                .foregroundStyle(isEarned ? Color.accent : .white.opacity(0.6))
                .lineLimit(2, reservesSpace: true)
            // Every card keeps the bar's room, so earned and locked cards in a row line up.
            progressBar(fraction(item, in: event))
                .opacity(isEarned ? 0 : 1)
        }
        .padding(10)
        .background(cardBackground(highlighted: isWorn))
    }

    /// The back of a card: what earns the item, how far the climber is, and when they earned it.
    private func back(_ item: UnlockItem, in event: UnlockEventProgress, isEarned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW IT'S EARNED")
                .font(.montserratBold(size: 10))
                .tracking(1.2)
                .foregroundStyle(Color.accent)
            Text(item.shape.title)
                .font(.montserratBold(size: 15))
                .foregroundStyle(.white)
            Text(howEarned(item, in: event.event))
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if isEarned {
                Label(earnedLine(item), systemImage: "checkmark.seal.fill")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(Color.accent)
            } else {
                Text(requirementLine(item, event: event))
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                progressBar(fraction(item, in: event))
            }
            Text((item.rarity ?? "core").uppercased())
                .font(.montserratBold(size: 9))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground(highlighted: false))
    }

    private func fraction(_ item: UnlockItem, in event: UnlockEventProgress) -> Double {
        if item.earn.metric == .onDay { return event.isEarned(item) ? 1 : 0 }
        return min(Double(event.value(of: item.earn.metric)) / Double(max(item.earn.threshold, 1)), 1)
    }

    private func progressBar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(Color.accent).frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 5)
    }

    private func cardBackground(highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(red: 0.07, green: 0.07, blue: 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(highlighted ? Color.accent : .white.opacity(0.08), lineWidth: highlighted ? 2 : 1)
            )
    }

    /// The rule in a sentence: "Climb 15 times in October."
    private func howEarned(_ item: UnlockItem, in event: UnlockEvent) -> String {
        let threshold = item.earn.threshold
        switch item.earn.metric {
        case .visits: return "Open Ascend in \(event.monthName)."
        case .climbs: return threshold == 1 ? "Finish a climb in \(event.monthName)." : "Finish \(threshold) climbs in \(event.monthName)."
        case .days: return threshold == event.dayCount() ? "Climb every day of \(event.monthName)." : "Climb on \(threshold) different days in \(event.monthName)."
        case .steps: return "Climb \(threshold.formatted()) steps in \(event.monthName)."
        case .onDay:
            let day = event.date(ofDay: threshold)?.formatted(.dateTime.month(.wide).day()) ?? "that day"
            return "Finish a climb on \(day)."
        }
    }

    private func earnedLine(_ item: UnlockItem) -> String {
        guard let date = unlocks.earnedAt[item.shape] else { return "Earned" }
        return "Earned \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// "4 / 10 climbs in October", "Climb Oct 31".
    private func requirementLine(_ item: UnlockItem, event: UnlockEventProgress) -> String {
        let value = event.value(of: item.earn.metric)
        let threshold = item.earn.threshold
        return switch item.earn.metric {
        case .visits: "Open Ascend in \(event.event.monthName)"
        case .climbs: "\(value) / \(threshold) climbs in \(event.event.monthName)"
        case .days: threshold == event.event.dayCount() ? "Climb every day of \(event.event.monthName): \(value) so far" : "\(value) / \(threshold) days climbed"
        case .steps: "\(value.formatted()) / \(threshold.formatted()) steps"
        case .onDay: UnlockCopy.requirement(item, in: event.event).capitalized
        }
    }

    private func badge(_ text: String, fill: Color) -> some View {
        Text(text)
            .font(.montserratBold(size: 10))
            .tracking(0.8)
            .foregroundStyle(.black)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(fill))
            .padding(8)
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            if model.saveFailed {
                Text("Couldn't save your athlete. Try again.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
            }
            Button {
                guard let userId else { return }
                Task {
                    if await model.save(userId: userId, to: store) {
                        dismiss()
                    }
                }
            } label: {
                Text(model.isSaving ? "SAVING..." : "SAVE ATHLETE")
                    .font(.montserratBold(size: 14))
                    .tracking(1.1)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accent.opacity(model.canSave ? 1 : 0.6)))
            }
            .buttonStyle(.plain)
            .disabled(!model.canSave || userId == nil)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(Color.black)
    }
}
