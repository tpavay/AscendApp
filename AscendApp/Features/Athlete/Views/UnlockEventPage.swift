import SwiftData
import SwiftUI

/// An event's own page, pushed from its Home card: what climbing this month earns, as ladders of
/// the items themselves, where the climber stands on each, and the way to put them on. Everything
/// it says comes from the catalogue, so November's event reuses it with no new screen.
struct UnlockEventPage: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var unlocks: UnlockStore
    @State private var looks: AthleteLookStore
    @State private var progress: UnlockEventProgress?
    @State private var openItem: UnlockItem?
    @State private var showingAthlete = false

    let event: UnlockEvent
    /// Leaves the page and starts a climb.
    let onStartClimbing: () -> Void
    private let userId: (() -> String?)?

    init(
        event: UnlockEvent,
        unlocks: UnlockStore = .shared,
        looks: AthleteLookStore = .shared,
        userId: (() -> String?)? = nil,
        onStartClimbing: @escaping () -> Void
    ) {
        self.event = event
        self.onStartClimbing = onStartClimbing
        self.userId = userId
        _unlocks = State(initialValue: unlocks)
        _looks = State(initialValue: looks)
    }

    private var signedInUser: String? {
        userId?() ?? authVM.user?.uid
    }

    private var ladders: [UnlockLadder] {
        progress.map { UnlockLadder.ladders(for: $0, owned: unlocks.earned) } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(ladders) { ladder in
                    ladderSection(ladder)
                        .padding(.top, 22)
                }
                athleteRow
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
            }
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(UnlockStyle.pageBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            startButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .trackOnce(screen: .unlockEvent)
        .navigationDestination(item: $openItem) { item in
            UnlockItemView(item: item, event: event, progress: progress, unlocks: unlocks, looks: looks, userId: userId, onStartClimbing: onStartClimbing)
        }
        .sheet(isPresented: $showingAthlete, onDismiss: reload) {
            AthleteEditorView(store: looks, unlocks: unlocks, userId: userId)
                .appSheetStyle(.large)
        }
        .task(id: signedInUser) {
            reload()
            if let userId = signedInUser { _ = await looks.load(userId: userId) }
        }
    }

    private func reload() {
        guard let userId = signedInUser else { return }
        progress = unlocks.refresh(userId: userId, modelContext: modelContext).first { $0.event == event }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            headerArt
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: UnlockStyle.pageBackground.opacity(0.6), location: 0),
                            .init(color: .clear, location: 0.26),
                            .init(color: .clear, location: 0.52),
                            .init(color: UnlockStyle.pageBackground, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: 8) {
                Text("\(event.title) is on.")
                    .font(.montserratBold(size: 32))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 2)
                    .accessibilityAddTraits(.isHeader)
                Text("Every climb and every step in \(event.monthName) earns something new.")
                    .font(.montserratBold(size: 12.5))
                    .tracking(-0.1)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
        .overlay(alignment: .top) {
            topBar
        }
    }

    @ViewBuilder
    private var headerArt: some View {
        if event.theme?.style == .haunted {
            Color.clear.overlay {
                Image("Seasonal/HauntedStairwell")
                    .resizable()
                    .scaledToFill()
            }
        } else {
            LinearGradient(colors: [UnlockStyle.pumpkin.opacity(0.25), UnlockStyle.pageBackground], startPoint: .top, endPoint: .bottom)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.black.opacity(0.5)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer(minLength: 0)
            Text(UnlockCopy.daysLeft(unlocks.daysLeft(in: event)))
                .font(.montserratBold(size: 11))
                .tracking(1.1)
                .monospacedDigit()
                .foregroundStyle(UnlockStyle.pumpkin)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule(style: .continuous).fill(UnlockStyle.pageBackground.opacity(0.72)))
                .overlay(Capsule(style: .continuous).strokeBorder(UnlockStyle.pumpkin.opacity(0.55), lineWidth: 1))
        }
        .padding(.horizontal, 15)
        .safeAreaPadding(.top)
        .padding(.top, 2)
    }

    // MARK: - Ladders

    private func ladderSection(_ ladder: UnlockLadder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(UnlockCopy.ladderTitle(ladder.kind, in: event))
                    .font(.montserratBold(size: 11))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.62))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                (Text(ladder.count.formatted()).foregroundStyle(UnlockStyle.pumpkin) + Text(" \(UnlockCopy.ladderUnit(ladder))").foregroundStyle(.white))
                    .font(.montserratBold(size: 13))
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)

            UnlockProgressBar(fraction: ladder.fraction, height: 6, fill: AnyShapeStyle(UnlockStyle.progressFill))
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .accessibilityHidden(true)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(ladder.items, id: \.id) { item in
                        UnlockItemTile(
                            item: item,
                            event: event,
                            state: ladder.state(of: item),
                            isWorn: looks.current.gear.contains(item.shape),
                            onOpen: { openItem = item }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Your Athlete and the button

    private var athleteRow: some View {
        let earned = unlocks.earnedItems(in: event)
        return Button {
            showingAthlete = true
        } label: {
            HStack(spacing: 12) {
                if let thumbnail = looks.current.wearing(.carry) ?? earned.last?.shape ?? (unlocks.catalog.visitItem(of: event) ?? unlocks.catalog.showcase(of: event).first)?.shape {
                    Image(thumbnail.thumbnailName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Athlete")
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(.white)
                    Text(earned.isEmpty ? "Climb to earn your first." : "\(earned.count) earned. Put them on.")
                        .font(.montserratBold(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your Athlete")
        .accessibilityValue(earned.isEmpty ? "Nothing earned yet" : "\(earned.count) earned")
        .accessibilityHint("Opens your athlete to put them on")
    }

    private var startButton: some View {
        UnlockDockButton(title: "START CLIMBING", style: .pumpkin, action: onStartClimbing)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: UnlockStyle.pageBackground, location: 0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            )
    }
}

/// A capsule progress bar.
struct UnlockProgressBar: View {
    let fraction: Double
    let height: CGFloat
    let fill: AnyShapeStyle
    var minimum: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(.white.opacity(0.1))
                Capsule(style: .continuous)
                    .fill(fill)
                    .frame(width: proxy.size.width * max(min(fraction, 1), fraction > 0 ? minimum : 0))
            }
        }
        .frame(height: height)
    }
}

/// The big pinned button an event's pages end on.
struct UnlockDockButton: View {
    enum Style {
        /// Orange, glowing: start a climb.
        case pumpkin
        /// Lime: put it on.
        case lime
        /// Outlined lime: it is on.
        case done
    }

    let title: String
    let style: Style
    var height: CGFloat = 54
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.montserratBold(size: height > 54 ? 16 : 15))
                .tracking(1)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(background)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var ink: Color {
        switch style {
        case .pumpkin: UnlockStyle.pumpkinInk
        case .lime: UnlockStyle.limeInk
        case .done: Color.accent
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        switch style {
        case .pumpkin:
            shape.fill(UnlockStyle.pumpkin).shadow(color: UnlockStyle.pumpkin.opacity(0.45), radius: 13)
        case .lime:
            shape.fill(Color.accent)
        case .done:
            shape.fill(Color.accent.opacity(0.14)).overlay(shape.strokeBorder(Color.accent.opacity(0.6), lineWidth: 1.5))
        }
    }
}
